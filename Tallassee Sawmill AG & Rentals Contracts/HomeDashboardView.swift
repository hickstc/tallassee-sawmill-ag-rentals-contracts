//
//  HomeDashboardView.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  The home screen: a business dashboard with today's jobs, fleet maintenance
//  status, a month-to-date business summary, and quick actions into every
//  module. Contract data comes from the JSON stores; maintenance data from
//  SwiftData.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Dashboard

/// Identifiable card sections for reordering
enum DashboardSection: String, Codable, Identifiable, CaseIterable {
    case fleetStatus
    case schedule
    case businessSummary
    case quickActions
    
    var id: String { rawValue }
}

struct HomeDashboardView: View {
    // Fleet status and the unified schedule, straight from SwiftData so
    // they live-update.
    @Query private var maintenanceTasks: [MaintenanceTask]
    @Query private var parts: [Part]
    @Query(sort: \ScheduledJob.date) private var scheduledJobs: [ScheduledJob]

    // Contract-side records, loaded from their JSON stores on appear/refresh.
    @State private var rentals: [RentalAgreementRecord] = []
    @State private var agJobs: [AgServicesRecord] = []
    @State private var millingJobs: [MillingJob] = []
    @State private var lumberOrders: [LumberOrder] = []

    /// Persisted card order; Quick Actions can be moved among other sections.
    @AppStorage("dashboardSectionOrder") private var sectionOrderData: Data = Data()
    @State private var sectionOrder: [DashboardSection] = []
    
    /// Track which card is being dragged
    @State private var draggingSection: DashboardSection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                
                ForEach(sectionOrder) { section in
                    cardView(for: section)
                        .onDrag {
                            if section == .quickActions {
                                draggingSection = section
                                return NSItemProvider(object: section.rawValue as NSString)
                            }
                            return NSItemProvider()
                        }
                        .onDrop(of: [.text], delegate: DropViewDelegate(
                            section: section,
                            sectionOrder: $sectionOrder,
                            draggingSection: $draggingSection,
                            onReorder: saveSectionOrder
                        ))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background { DashboardBackground() }
        .navigationTitle("Tallassee Sawmill")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if sectionOrder.isEmpty {
                loadSectionOrder()
            }
            reload()
        }
        .refreshable { reload() }
    }

    private func reload() {
        rentals = RentalAgreementStorage.loadAll()
        agJobs = AgServicesStorage.loadAll()
        millingJobs = MillingJobStorage.loadAll()
        lumberOrders = OrderStorage.load()
    }
    
    /// Returns the appropriate card view for each section
    @ViewBuilder
    private func cardView(for section: DashboardSection) -> some View {
        switch section {
        case .fleetStatus:
            fleetStatusCard
        case .schedule:
            todaysJobsCard
        case .businessSummary:
            businessSummaryCard
        case .quickActions:
            quickActionsCard
                .opacity(draggingSection == .quickActions ? 0.85 : 1.0)
        }
    }
    
    /// Load section order from UserDefaults or use default
    private func loadSectionOrder() {
        if let decoded = try? JSONDecoder().decode([DashboardSection].self, from: sectionOrderData),
           !decoded.isEmpty {
            sectionOrder = decoded
        } else {
            // Default order
            sectionOrder = [.fleetStatus, .schedule, .businessSummary, .quickActions]
        }
    }
    
    /// Save section order to UserDefaults
    private func saveSectionOrder() {
        if let encoded = try? JSONEncoder().encode(sectionOrder) {
            sectionOrderData = encoded
        }
    }

    // MARK: Header

    private var header: some View {
        Text(Date.now.formatted(date: .complete, time: .omitted))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: Fleet status

    private var buckets: DashboardBuckets { DashboardBuckets(tasks: maintenanceTasks) }
    private var lowStockCount: Int { parts.filter(\.isLowStock).count }

    /// Red/orange/green maintenance banner; tapping opens the module.
    private var fleetStatusCard: some View {
        let overdue = buckets.overdue.count
        let dueSoon = buckets.dueSoon.count
        let tone: Color = overdue > 0 ? .red : (dueSoon > 0 || lowStockCount > 0 ? .orange : .green)

        var message: String {
            var pieces: [String] = []
            if overdue > 0 { pieces.append("\(overdue) overdue") }
            if dueSoon > 0 { pieces.append("\(dueSoon) due soon") }
            if lowStockCount > 0 { pieces.append("\(lowStockCount) low stock") }
            return pieces.isEmpty ? "Fleet is up to date" : pieces.joined(separator: " · ")
        }

        return NavigationLink(value: ContractType.maintenance) {
            DashboardCard {
                HStack(spacing: 12) {
                    Image(systemName: overdue > 0
                          ? "exclamationmark.triangle.fill"
                          : (dueSoon > 0 || lowStockCount > 0 ? "clock.badge.exclamationmark.fill" : "checkmark.seal.fill"))
                        .font(.title2)
                        .foregroundStyle(tone)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fleet Maintenance")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(tone)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Schedule (today / overdue / upcoming)

    /// The unified scheduler drives this card: jobs of every type plus
    /// date-based equipment maintenance.
    private var todaysJobsCard: some View {
        let buckets = ScheduleBuckets(jobs: scheduledJobs, tasks: maintenanceTasks)

        return DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Schedule")
                        .font(.headline)
                    Spacer()
                    NavigationLink(value: ContractType.scheduler) {
                        Text("Open Scheduler")
                            .font(.subheadline)
                    }
                }

                if !buckets.overdue.isEmpty {
                    Label("\(buckets.overdue.count) overdue job\(buckets.overdue.count == 1 ? "" : "s")",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }

                if buckets.today.isEmpty {
                    Text("Nothing scheduled for today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(buckets.today) { entry in
                        scheduleRow(entry)
                    }
                }

                if !buckets.upcoming.isEmpty {
                    Divider()
                    Text("Up Next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(buckets.upcoming.prefix(3)) { entry in
                        scheduleRow(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleRow(_ entry: ScheduleEntry) -> some View {
        NavigationLink(value: entry.maintenanceTask == nil
                       ? ContractType.scheduler
                       : ContractType.maintenance) {
            HStack(spacing: 10) {
                if let job = entry.job {
                    JobRow(job: job, compact: true)
                } else if let task = entry.maintenanceTask {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(task.equipment?.name ?? "Equipment"): \(task.name)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(task.dueSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Business summary (month to date)

    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: .now)
            ?? DateInterval(start: .now, duration: 0)
    }

    private var summaryMetrics: [(label: String, value: String, icon: String)] {
        let month = monthInterval

        let rentalRevenue = rentals
            .filter { month.contains($0.data.startDate) }
            .reduce(0.0) { $0 + $1.data.subtotal }
        let agRevenue = agJobs
            .filter { month.contains($0.data.startDate) }
            .reduce(0.0) { $0 + $1.data.estimatedTotal }
        let lumberRevenue = lumberOrders
            .filter { month.contains($0.createdAt) }
            .reduce(0.0) { $0 + $1.subtotal }
        let milled = millingJobs
            .filter { month.contains($0.date) }
            .reduce(0.0) { $0 + $1.totalBF }

        return [
            ("Rentals", currencyString(rentalRevenue), "house.fill"),
            ("Ag Services", currencyString(agRevenue), "leaf.fill"),
            ("Lumber Orders", currencyString(lumberRevenue), "list.bullet.rectangle"),
            ("Board Feet Milled", milled.formatted(.number.precision(.fractionLength(0))), "tree.fill"),
        ]
    }

    private var businessSummaryCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("This Month")
                        .font(.headline)
                    Spacer()
                    NavigationLink(value: ContractType.financials) {
                        Text("Full Report")
                            .font(.subheadline)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(summaryMetrics, id: \.label) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(metric.label, systemImage: metric.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(metric.value)
                                .font(.title3.bold())
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .glassTile(cornerRadius: 12)
                    }
                }
            }
        }
    }

    // MARK: Quick actions

    private var quickActionsCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Quick Actions")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "hand.draw")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Press & hold to move")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 10) {
                    ForEach(ContractType.allCases) { type in
                        NavigationLink(value: type) {
                            VStack(spacing: 6) {
                                Image(systemName: type.systemImage)
                                    .font(.title3)
                                    .frame(height: 24)
                                Text(type.title)
                                    .font(.subheadline.weight(.medium))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2, reservesSpace: true)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 2)
                            .glassTile(cornerRadius: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Drag & Drop Support

/// Handles drop operations for reordering dashboard sections
struct DropViewDelegate: DropDelegate {
    let section: DashboardSection
    @Binding var sectionOrder: [DashboardSection]
    @Binding var draggingSection: DashboardSection?
    let onReorder: () -> Void
    
    func dropEntered(info: DropInfo) {
        guard let draggingSection = draggingSection,
              draggingSection != section,
              let fromIndex = sectionOrder.firstIndex(of: draggingSection),
              let toIndex = sectionOrder.firstIndex(of: section) else {
            return
        }
        
        if fromIndex != toIndex {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                sectionOrder.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggingSection = nil
        onReorder()
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Glass styling

/// Full-screen gradient backdrop (forest green → warm wood brown) that makes
/// the frosted glass cards pop. Features the app logo as a large, dark, clearly
/// visible design element that remains readable beneath the frosted cards.
private struct DashboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Base layer adapts to system appearance
            Color(.systemGroupedBackground)
            
            // Forest-green to wood-brown gradient with professional opacity
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle radial accent for organic depth
            RadialGradient(
                colors: [
                    Color.green.opacity(colorScheme == .dark ? 0.15 : 0.12),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 400
            )
            
            RadialGradient(
                colors: [
                    Color.brown.opacity(colorScheme == .dark ? 0.12 : 0.10),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 400
            )
            
            // App logo: large, dark, and clearly visible as a design element.
            // The frosted glass cards provide sufficient blur for text readability.
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 600, maxHeight: 600)
                .opacity(colorScheme == .dark ? 0.25 : 0.35)
                .blendMode(colorScheme == .dark ? .softLight : .multiply)
                .allowsHitTesting(false)  // Never intercepts taps
        }
        .ignoresSafeArea()
    }
    
    private var gradientColors: [Color] {
        if colorScheme == .dark {
            // Dark mode: deeper tones with more saturation for visibility
            return [
                Color(red: 0.15, green: 0.35, blue: 0.20),  // Forest green
                Color(red: 0.12, green: 0.20, blue: 0.15),  // Dark green-brown
                Color(red: 0.25, green: 0.18, blue: 0.12),  // Wood brown
            ]
        } else {
            // Light mode: softer, warmer tones that don't overpower
            return [
                Color(red: 0.88, green: 0.95, blue: 0.90),  // Soft sage
                Color(red: 0.96, green: 0.94, blue: 0.88),  // Warm cream
                Color(red: 0.92, green: 0.88, blue: 0.80),  // Wood tan
            ]
        }
    }
}

/// Shared glass-card look for all dashboard sections: translucent material,
/// hairline border, and a soft shadow for gentle depth.
private struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

/// Small translucent tile used inside cards (metrics, quick actions).
private struct GlassTile: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

private extension View {
    func glassTile(cornerRadius: CGFloat) -> some View {
        modifier(GlassTile(cornerRadius: cornerRadius))
    }
}

#Preview {
    NavigationStack {
        HomeDashboardView()
    }
    .modelContainer(MaintenanceStore.container)
}
