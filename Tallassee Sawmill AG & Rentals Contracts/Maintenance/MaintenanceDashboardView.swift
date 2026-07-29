//
//  MaintenanceDashboardView.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Entry point for the Maintenance module: color-coded dashboard with
//  overdue / due soon / recently completed, plus links to the fleet and
//  the master parts library.
//

import SwiftUI
import SwiftData

struct MaintenanceView: View {
    @Query private var tasks: [MaintenanceTask]
    @Query(sort: \MaintenanceLog.date, order: .reverse) private var logs: [MaintenanceLog]
    @Query private var equipment: [Equipment]
    @Query private var parts: [Part]

    /// Parts/fluids at or below their low-stock warning level.
    private var lowStockParts: [Part] {
        parts.filter(\.isLowStock).sorted { $0.partDescription < $1.partDescription }
    }

    var body: some View {
        // Bucketing lives in DashboardBuckets (MVVM) so it stays testable.
        let buckets = DashboardBuckets(tasks: tasks)
        let recent = DashboardBuckets.recentLogs(logs)

        List {
            summarySection(buckets)

            if !buckets.overdue.isEmpty {
                taskSection("Overdue", entries: buckets.overdue)
            }
            if !buckets.dueSoon.isEmpty {
                taskSection("Due Soon", entries: buckets.dueSoon)
            }

            if !lowStockParts.isEmpty {
                Section("Low Stock") {
                    ForEach(lowStockParts, id: \.uuid) { part in
                        NavigationLink {
                            PartDetailView(part: part)
                        } label: {
                            HStack {
                                Label(part.partDescription, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Spacer()
                                Text("\(part.stockSummary) left")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Recently Completed") {
                if recent.isEmpty {
                    Text("No services completed in the last 30 days.")
                        .foregroundStyle(.secondary)
                }
                ForEach(recent.prefix(10), id: \.uuid) { log in
                    NavigationLink {
                        MaintenanceLogDetailView(log: log)
                    } label: {
                        MaintenanceLogRow(log: log, showsContext: true)
                    }
                }
            }

            Section("Browse") {
                NavigationLink {
                    EquipmentListView()
                } label: {
                    Label {
                        Text("Equipment")
                    } icon: {
                        Image(systemName: "wrench.and.screwdriver.fill")
                    }
                    .badge(equipment.count)
                }
                NavigationLink {
                    PartsLibraryView()
                } label: {
                    Label {
                        Text("Parts Library")
                    } icon: {
                        Image(systemName: "shippingbox.fill")
                    }
                    .badge(parts.count)
                }
                NavigationLink {
                    MaintenanceReportsView()
                } label: {
                    Label {
                        Text("Reports")
                    } icon: {
                        Image(systemName: "doc.text.fill")
                    }
                }
            }
        }
        .navigationTitle("Maintenance")
    }

    /// Three color-coded count cards across the top.
    private func summarySection(_ buckets: DashboardBuckets) -> some View {
        Section {
            HStack(spacing: 12) {
                StatusCountCard(count: buckets.overdue.count, status: .overdue)
                StatusCountCard(count: buckets.dueSoon.count, status: .dueSoon)
                StatusCountCard(count: buckets.upToDate.count, status: .upToDate)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func taskSection(_ title: String, entries: [DashboardEntry]) -> some View {
        Section(title) {
            ForEach(entries) { entry in
                NavigationLink {
                    MaintenanceTaskDetailView(task: entry.task)
                } label: {
                    MaintenanceTaskRow(task: entry.task, showsEquipment: true)
                }
            }
        }
    }
}

/// One of the dashboard's summary tiles ("3 Overdue" in red, etc.).
private struct StatusCountCard: View {
    let count: Int
    let status: MaintenanceStatus

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.title3)
            Text("\(count)")
                .font(.title2.bold())
            Text(status.label)
                .font(.caption)
        }
        .foregroundStyle(status.color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        MaintenanceView()
    }
    .modelContainer(MaintenanceStore.container)
}
