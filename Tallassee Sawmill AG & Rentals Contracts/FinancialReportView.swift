import SwiftUI
import UIKit
import Charts

// MARK: - Report period

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case thisMonth = "This Month"
    case last30Days = "Last 30 Days"
    case thisYear = "This Year"
    case allTime = "All Time"

    var id: String { rawValue }

    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .last30Days:
            guard let cutoff = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return date >= cutoff
        case .thisYear:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
        case .allTime:
            return true
        }
    }
}

// MARK: - Report entry

private struct ReportEntry: Identifiable {
    enum Category: String, CaseIterable {
        case rentals = "Rentals"
        case agServices = "Ag Services"
        case lumberOrders = "Lumber Orders"
        case milling = "Log Milling"
    }

    let id: UUID
    let category: Category
    let customer: String
    let date: Date
    let amount: Double
    /// False for unsigned rental/ag drafts. Lumber orders are always considered final.
    let isSigned: Bool
}

// MARK: - View

/// Revenue summary across saved rental agreements, ag service agreements, and lumber orders.
struct FinancialReportView: View {
    @AppStorage("salesTaxPercent") private var taxPercent: Double = 6.5

    @State private var entries: [ReportEntry] = []
    @State private var millingJobs: [(date: Date, boardFeet: Double)] = []
    @State private var period: ReportPeriod = .thisMonth
    @State private var excludeDrafts = false
    @State private var shareItem: ShareItem?

    private var filteredEntries: [ReportEntry] {
        entries.filter { period.contains($0.date) && (!excludeDrafts || $0.isSigned) }
    }

    private var categoryTotals: [(category: ReportEntry.Category, total: Double)] {
        ReportEntry.Category.allCases.map { category in
            (category, filteredEntries.filter { $0.category == category }.reduce(0) { $0 + $1.amount })
        }
    }

    private var grandTotal: Double {
        filteredEntries.reduce(0) { $0 + $1.amount }
    }

    private var millingTotalBF: Double {
        millingJobs.filter { period.contains($0.date) }.reduce(0) { $0 + $1.boardFeet }
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(ReportPeriod.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                Toggle("Exclude unsigned drafts", isOn: $excludeDrafts)
            } footer: {
                Text("Rental and ag service agreements without a signature count as drafts. Lumber orders and milling jobs are always included.")
            }

            Section("Summary") {
                ForEach(categoryTotals, id: \.category) { item in
                    LabeledContent(item.category.rawValue, value: currencyString(item.total))
                }
                LabeledContent("Total", value: currencyString(grandTotal))
                    .font(.headline)
                LabeledContent("Milled Board Feet") {
                    Text("\(millingTotalBF.formatted(.number.precision(.fractionLength(0...2)))) BF")
                        .foregroundStyle(.secondary)
                }
            }

            if grandTotal > 0 {
                Section("Breakdown") {
                    Chart(categoryTotals.filter { $0.total > 0 }, id: \.category) { item in
                        SectorMark(angle: .value("Amount", item.total),
                                   innerRadius: .ratio(0.55),
                                   angularInset: 1.5)
                            .foregroundStyle(by: .value("Category", item.category.rawValue))
                            .cornerRadius(3)
                    }
                    .frame(height: 220)
                    .padding(.vertical, 8)
                }
            }

            ForEach(ReportEntry.Category.allCases, id: \.self) { category in
                let rows = filteredEntries.filter { $0.category == category }
                if !rows.isEmpty {
                    Section(category.rawValue) {
                        ForEach(rows) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.customer.isEmpty ? "Unnamed" : entry.customer)
                                    HStack(spacing: 6) {
                                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        if !entry.isSigned {
                                            Text("Draft")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(currencyString(entry.amount))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }

            if filteredEntries.isEmpty {
                Section {
                    Text("No saved agreements or orders in this period. Signed agreements and lumber orders appear here automatically.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Financial Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = makePDF() { shareItem = ShareItem(url: url) }
                } label: {
                    Label("Share Report (PDF)", systemImage: "square.and.arrow.up")
                }
                .disabled(filteredEntries.isEmpty)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .onAppear(perform: loadData)
    }

    // MARK: - Data

    private func loadData() {
        var result: [ReportEntry] = []

        for rec in RentalAgreementStorage.loadAll() {
            result.append(ReportEntry(id: rec.id,
                                      category: .rentals,
                                      customer: rec.customerName,
                                      date: rec.signedAt ?? rec.updatedAt,
                                      amount: rec.data.totalWithTax(percent: taxPercent),
                                      isSigned: rec.signedAt != nil))
        }
        for rec in AgServicesStorage.loadAll() {
            result.append(ReportEntry(id: rec.id,
                                      category: .agServices,
                                      customer: rec.customerName,
                                      date: rec.signedAt ?? rec.updatedAt,
                                      amount: rec.data.estimatedTotal,
                                      isSigned: rec.signedAt != nil))
        }
        for order in OrderStorage.load() {
            result.append(ReportEntry(id: order.id,
                                      category: .lumberOrders,
                                      customer: order.customerName,
                                      date: order.createdAt,
                                      amount: order.grandTotal(percent: taxPercent),
                                      isSigned: true))
        }
        let jobs = MillingJobStorage.loadAll()
        for job in jobs {
            result.append(ReportEntry(id: job.id,
                                      category: .milling,
                                      customer: job.customerName,
                                      date: job.date,
                                      amount: job.totalPrice,
                                      isSigned: true))
        }

        entries = result.sorted { $0.date > $1.date }
        millingJobs = jobs.map { ($0.date, $0.totalBF) }
    }

    // MARK: - PDF export

    private func makePDF() -> URL? {
        let doc = NSMutableAttributedString()

        func append(_ text: String,
                    font: UIFont,
                    spacingAfter: CGFloat = 6,
                    color: UIColor = .black) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = spacingAfter
            doc.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]))
        }

        append("Tallassee Sawmill, AG & Rental Services", font: .boldSystemFont(ofSize: 18), spacingAfter: 2)
        append("871 County Rd. 77, Tallassee, AL 36078  ·  334-524-3601",
               font: .systemFont(ofSize: 10), spacingAfter: 16, color: .darkGray)

        append("Financial Report — \(period.rawValue)", font: .boldSystemFont(ofSize: 15), spacingAfter: 2)
        append("Generated \(Date().formatted(date: .long, time: .shortened))",
               font: .systemFont(ofSize: 10), spacingAfter: 14, color: .darkGray)

        for category in ReportEntry.Category.allCases {
            let rows = filteredEntries.filter { $0.category == category }
            guard !rows.isEmpty else { continue }
            append(category.rawValue, font: .boldSystemFont(ofSize: 13), spacingAfter: 4)
            for entry in rows {
                let name = entry.customer.isEmpty ? "Unnamed" : entry.customer
                let draft = entry.isSigned ? "" : "  (draft)"
                append("\(entry.date.formatted(date: .abbreviated, time: .omitted))   \(name)\(draft)        \(currencyString(entry.amount))",
                       font: .systemFont(ofSize: 11), spacingAfter: 1)
            }
            let total = rows.reduce(0) { $0 + $1.amount }
            append("Subtotal:  \(currencyString(total))", font: .boldSystemFont(ofSize: 11), spacingAfter: 10)
        }

        append("Grand Total:  \(currencyString(grandTotal))", font: .boldSystemFont(ofSize: 15), spacingAfter: 10)

        if millingTotalBF > 0 {
            append("Milled: \(millingTotalBF.formatted(.number.precision(.fractionLength(0...2)))) board feet",
                   font: .italicSystemFont(ofSize: 10), color: .darkGray)
        }

        let stem = period.rawValue.replacingOccurrences(of: " ", with: "-")
        return PDFRenderer.write(doc, fileName: "Financial-Report-\(stem).pdf")
    }
}

#Preview {
    NavigationStack { FinancialReportView() }
}
