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

// MARK: - Dashboard

struct HomeDashboardView: View {
    // Fleet status straight from SwiftData so it live-updates.
    @Query private var maintenanceTasks: [MaintenanceTask]
    @Query private var parts: [Part]

    // Contract-side records, loaded from their JSON stores on appear/refresh.
    @State private var rentals: [RentalAgreementRecord] = []
    @State private var agJobs: [AgServicesRecord] = []
    @State private var millingJobs: [MillingJob] = []
    @State private var lumberOrders: [LumberOrder] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                fleetStatusCard
                todaysJobsCard
                businessSummaryCard
                quickActionsCard
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tallassee Sawmill")
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: reload)
        .refreshable { reload() }
    }

    private func reload() {
        rentals = RentalAgreementStorage.loadAll()
        agJobs = AgServicesStorage.loadAll()
        millingJobs = MillingJobStorage.loadAll()
        lumberOrders = OrderStorage.load()
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

    // MARK: Today's jobs

    /// A unified row for anything happening today, from any module.
    private struct TodayJob: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let destination: ContractType
    }

    private var todaysJobs: [TodayJob] {
        let calendar = Calendar.current
        var jobs: [TodayJob] = []

        for rental in rentals where calendar.isDateInToday(rental.data.startDate) {
            jobs.append(TodayJob(
                id: "rental-\(rental.id)",
                title: rental.customerName.isEmpty ? "Rental" : rental.customerName,
                subtitle: "Rental starts \(rental.data.startDate.formatted(date: .omitted, time: .shortened))",
                systemImage: "house.fill",
                destination: .rental
            ))
        }
        for job in agJobs where calendar.isDateInToday(job.data.startDate) {
            jobs.append(TodayJob(
                id: "ag-\(job.id)",
                title: job.customerName.isEmpty ? "Ag Services" : job.customerName,
                subtitle: "Ag services job",
                systemImage: "leaf.fill",
                destination: .ag
            ))
        }
        for job in millingJobs where calendar.isDateInToday(job.date) {
            jobs.append(TodayJob(
                id: "milling-\(job.id)",
                title: job.customerName.isEmpty ? "Milling" : job.customerName,
                subtitle: "Milling · \(job.totalBF.formatted(.number.precision(.fractionLength(0...1)))) BF",
                systemImage: "tree.fill",
                destination: .milling
            ))
        }
        return jobs
    }

    private var todaysJobsCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today's Jobs")
                    .font(.headline)
                if todaysJobs.isEmpty {
                    Text("Nothing scheduled for today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(todaysJobs) { job in
                        NavigationLink(value: job.destination) {
                            HStack(spacing: 10) {
                                Image(systemName: job.systemImage)
                                    .foregroundStyle(.tint)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(job.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(job.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
                        .background(Color(.tertiarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    // MARK: Quick actions

    private var quickActionsCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Actions")
                    .font(.headline)
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
                            .background(Color(.tertiarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Card container

/// Shared rounded-card look for all dashboard sections.
private struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    NavigationStack {
        HomeDashboardView()
    }
    .modelContainer(MaintenanceStore.container)
}
