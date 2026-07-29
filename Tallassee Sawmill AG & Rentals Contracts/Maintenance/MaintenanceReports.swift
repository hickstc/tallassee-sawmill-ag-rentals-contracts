//
//  MaintenanceReports.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  PDF reporting for the maintenance module. A small table-based PDF builder
//  (US Letter, logo header, date, page numbers, repeating column headers)
//  plus the four fleet reports and the screen that generates them.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - PDF building blocks

/// One table cell: text plus optional emphasis/color (used for status columns).
struct PDFCell {
    var text: String
    var color: UIColor = .label
    var bold = false

    init(_ text: String, color: UIColor = .label, bold: Bool = false) {
        self.text = text
        self.color = color
        self.bold = bold
    }
}

/// A table column: header title and relative width (weights are normalized).
struct PDFColumn {
    var title: String
    var weight: CGFloat

    init(_ title: String, weight: CGFloat) {
        self.title = title
        self.weight = weight
    }
}

// MARK: - PDF Builder

/// Draws paginated, print-friendly PDF reports on US Letter paper with the
/// company logo, report title, generation date, and page numbers. Tables
/// repeat their header row after every page break.
final class MaintenancePDFBuilder {
    private let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72 dpi
    private let margin: CGFloat = 48
    private let headerBottom: CGFloat = 106
    private let footerTop: CGFloat = 748

    private let title: String
    private var context: UIGraphicsPDFRendererContext?
    private var y: CGFloat = 0
    private var pageNumber = 0

    private var contentWidth: CGFloat { pageRect.width - margin * 2 }

    init(title: String) {
        self.title = title
    }

    /// Renders the report into a temporary file and returns its URL.
    func render(fileName: String, content: (MaintenancePDFBuilder) -> Void) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            self.context = ctx
            startPage()
            content(self)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Page chrome

    private func startPage() {
        guard let context else { return }
        context.beginPage()
        pageNumber += 1
        drawPageHeader()
        drawPageFooter()
        y = headerBottom + 6
    }

    private func drawPageHeader() {
        // Logo, right-aligned, preserving aspect ratio.
        if let logo = UIImage(named: "Logo"), logo.size.height > 0 {
            let height: CGFloat = 44
            let width = height * (logo.size.width / logo.size.height)
            logo.draw(in: CGRect(x: pageRect.width - margin - width, y: 40, width: width, height: height))
        }

        (title as NSString).draw(
            at: CGPoint(x: margin, y: 44),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 19, weight: .bold),
                .foregroundColor: UIColor.label,
            ]
        )
        let dateLine = "Generated \(Date.now.formatted(date: .long, time: .shortened))"
        (dateLine as NSString).draw(
            at: CGPoint(x: margin, y: 70),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )
        drawRule(at: headerBottom - 6)
    }

    private func drawPageFooter() {
        drawRule(at: footerTop)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        ("Tallassee Sawmill AG & Rentals" as NSString).draw(
            at: CGPoint(x: margin, y: footerTop + 6), withAttributes: attributes
        )
        let pageText = "Page \(pageNumber)" as NSString
        let size = pageText.size(withAttributes: attributes)
        pageText.draw(
            at: CGPoint(x: pageRect.width - margin - size.width, y: footerTop + 6),
            withAttributes: attributes
        )
    }

    private func drawRule(at ruleY: CGFloat, color: UIColor = .separator) {
        guard let cg = context?.cgContext else { return }
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: margin, y: ruleY))
        cg.addLine(to: CGPoint(x: pageRect.width - margin, y: ruleY))
        cg.strokePath()
    }

    /// Starts a new page when `height` more points would overrun the footer.
    private func ensureSpace(_ height: CGFloat) {
        if y + height > footerTop - 8 {
            startPage()
        }
    }

    // MARK: Content primitives

    func sectionTitle(_ text: String) {
        ensureSpace(34)
        y += 8
        (text as NSString).draw(
            at: CGPoint(x: margin, y: y),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.label,
            ]
        )
        y += 20
    }

    /// Word-wrapped paragraph text.
    func paragraph(_ text: String, size: CGFloat = 10, color: UIColor = .label, spacingAfter: CGFloat = 6) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size),
            .foregroundColor: color,
        ]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let height = ceil(bounds.height)
        ensureSpace(height + spacingAfter)
        (text as NSString).draw(
            with: CGRect(x: margin, y: y, width: contentWidth, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        y += height + spacingAfter
    }

    /// "Label: value" info line for report headers (machine specs etc.).
    func infoLine(_ label: String, _ value: String) {
        paragraph("\(label): \(value)", size: 10, spacingAfter: 3)
    }

    // MARK: Tables

    private let cellFont = UIFont.systemFont(ofSize: 9)
    private let cellBoldFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
    private let cellPadding: CGFloat = 4
    /// Cells wrap up to ~3 lines, then clip, so rows stay compact.
    private let maxCellHeight: CGFloat = 34

    /// Draws a full table with a shaded, repeating header row and hairline
    /// row separators.
    func table(columns: [PDFColumn], rows: [[PDFCell]]) {
        let widths = columnWidths(columns)

        ensureSpace(60) // header plus at least one row before breaking
        drawTableHeader(columns, widths: widths)

        for row in rows {
            let height = rowHeight(row, widths: widths)
            if y + height > footerTop - 8 {
                startPage()
                drawTableHeader(columns, widths: widths)
            }
            drawRow(row, widths: widths, height: height)
        }
        y += 8
    }

    private func columnWidths(_ columns: [PDFColumn]) -> [CGFloat] {
        let totalWeight = columns.reduce(0) { $0 + $1.weight }
        return columns.map { contentWidth * ($0.weight / max(totalWeight, 0.001)) }
    }

    private func drawTableHeader(_ columns: [PDFColumn], widths: [CGFloat]) {
        let height: CGFloat = 18
        if let cg = context?.cgContext {
            cg.setFillColor(UIColor.systemGray5.cgColor)
            cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: height))
        }
        var x = margin
        for (index, column) in columns.enumerated() {
            (column.title as NSString).draw(
                with: CGRect(x: x + cellPadding, y: y + 4,
                             width: widths[index] - cellPadding * 2, height: height - 6),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: UIFont.systemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: UIColor.label,
                ],
                context: nil
            )
            x += widths[index]
        }
        y += height
    }

    private func rowHeight(_ row: [PDFCell], widths: [CGFloat]) -> CGFloat {
        var tallest: CGFloat = 12
        for (index, cell) in row.enumerated() where index < widths.count {
            let bounds = (cell.text as NSString).boundingRect(
                with: CGSize(width: widths[index] - cellPadding * 2, height: maxCellHeight),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: cell.bold ? cellBoldFont : cellFont],
                context: nil
            )
            tallest = max(tallest, min(ceil(bounds.height), maxCellHeight))
        }
        return tallest + cellPadding * 2
    }

    private func drawRow(_ row: [PDFCell], widths: [CGFloat], height: CGFloat) {
        var x = margin
        for (index, cell) in row.enumerated() where index < widths.count {
            (cell.text as NSString).draw(
                with: CGRect(x: x + cellPadding, y: y + cellPadding,
                             width: widths[index] - cellPadding * 2,
                             height: height - cellPadding * 2),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: cell.bold ? cellBoldFont : cellFont,
                    .foregroundColor: cell.color,
                ],
                context: nil
            )
            x += widths[index]
        }
        y += height
        drawRule(at: y, color: UIColor.separator.withAlphaComponent(0.5))
    }
}

// MARK: - Report generators

private let reportCurrencyCode = Locale.current.currency?.identifier ?? "USD"

private func money(_ value: Decimal?) -> String {
    value?.formatted(.currency(code: reportCurrencyCode)) ?? "—"
}

private func meterText(_ value: Double?, unit: String) -> String {
    guard let value else { return "—" }
    return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
}

private extension MaintenanceStatus {
    var reportColor: UIColor {
        switch self {
        case .overdue: return .systemRed
        case .dueSoon: return .systemOrange
        case .upToDate: return .systemGreen
        case .notScheduled: return .systemGray
        }
    }
}

@MainActor
enum MaintenanceReports {

    /// Full maintenance history for one machine: specs, the service schedule
    /// (intervals, last done, next due), and every recorded service.
    static func machineHistory(_ equipment: Equipment) -> URL? {
        let builder = MaintenancePDFBuilder(title: "Maintenance History — \(equipment.name)")
        let stem = safeFileStem(equipment.name, fallback: "machine")
        return builder.render(fileName: "\(stem)-maintenance-history.pdf") { pdf in
            let unit = equipment.meterType.unitAbbreviation

            pdf.sectionTitle("Machine")
            pdf.infoLine("Make / Model", "\(equipment.make) \(equipment.model)"
                .trimmingCharacters(in: .whitespaces))
            if let year = equipment.year { pdf.infoLine("Year", String(year)) }
            if !equipment.serialOrVIN.isEmpty { pdf.infoLine("Serial / VIN", equipment.serialOrVIN) }
            pdf.infoLine("Current \(equipment.meterType.rawValue)", equipment.meterSummary)
            if let purchased = equipment.purchaseDate {
                pdf.infoLine("Purchased", purchased.formatted(date: .abbreviated, time: .omitted))
            }

            // Service schedule: intervals, last done, next due.
            let tasks = equipment.sortedTasks
            pdf.sectionTitle("Service Schedule")
            if tasks.isEmpty {
                pdf.paragraph("No maintenance items defined.", color: .secondaryLabel)
            } else {
                let columns = [
                    PDFColumn("Maintenance Item", weight: 0.26),
                    PDFColumn("Interval", weight: 0.2),
                    PDFColumn("Last Done", weight: 0.19),
                    PDFColumn("Next Due", weight: 0.22),
                    PDFColumn("Status", weight: 0.13),
                ]
                let rows = tasks.map { task -> [PDFCell] in
                    var interval: [String] = []
                    if let meter = task.intervalMeter {
                        interval.append("\(meter.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                    }
                    if let days = task.intervalDays { interval.append("\(days) days") }

                    var lastDone: [String] = []
                    if let date = task.lastDoneDate {
                        lastDone.append(date.formatted(date: .numeric, time: .omitted))
                    }
                    if let meter = task.lastDoneMeter { lastDone.append(meterText(meter, unit: unit)) }

                    var nextDue: [String] = []
                    if let date = task.nextDueDate {
                        nextDue.append(date.formatted(date: .numeric, time: .omitted))
                    }
                    if let meter = task.nextDueMeter { nextDue.append(meterText(meter, unit: unit)) }

                    let status = task.status()
                    return [
                        PDFCell(task.name),
                        PDFCell(interval.isEmpty ? "—" : interval.joined(separator: " / ")),
                        PDFCell(lastDone.isEmpty ? "Never" : lastDone.joined(separator: " @ ")),
                        PDFCell(nextDue.isEmpty ? "—" : nextDue.joined(separator: " @ ")),
                        PDFCell(status.label, color: status.reportColor, bold: true),
                    ]
                }
                pdf.table(columns: columns, rows: rows)
            }

            // Every recorded service across all of the machine's items.
            let logs = tasks.flatMap { $0.sortedLogs }.sorted { $0.date > $1.date }
            pdf.sectionTitle("Service History")
            if logs.isEmpty {
                pdf.paragraph("No services recorded.", color: .secondaryLabel)
            } else {
                let columns = [
                    PDFColumn("Date", weight: 0.11),
                    PDFColumn("Maintenance Item", weight: 0.2),
                    PDFColumn("Meter", weight: 0.11),
                    PDFColumn("Cost", weight: 0.1),
                    PDFColumn("Parts Used", weight: 0.24),
                    PDFColumn("Notes", weight: 0.24),
                ]
                let rows = logs.map { log -> [PDFCell] in
                    [
                        PDFCell(log.date.formatted(date: .numeric, time: .omitted)),
                        PDFCell(log.task?.name ?? "—"),
                        PDFCell(meterText(log.meterAtService, unit: unit)),
                        PDFCell(money(log.cost)),
                        PDFCell(log.partsUsedSummary.isEmpty ? "—" : log.partsUsedSummary),
                        PDFCell(log.notes.isEmpty ? "—" : log.notes),
                    ]
                }
                pdf.table(columns: columns, rows: rows)

                let total = logs.compactMap(\.cost).reduce(Decimal(0), +)
                pdf.paragraph("Total recorded maintenance cost: \(money(total))", size: 10)
            }
        }
    }

    /// Every scheduled maintenance item across the fleet, worst first.
    static func serviceDue(equipment: [Equipment]) -> URL? {
        let builder = MaintenancePDFBuilder(title: "Service Due Report")
        return builder.render(fileName: "service-due-report.pdf") { pdf in
            let entries = equipment
                .flatMap { $0.sortedTasks }
                .filter { $0.intervalMeter != nil || $0.intervalDays != nil }
                .map { (task: $0, status: $0.status()) }
                .sorted {
                    if $0.status != $1.status { return $0.status < $1.status }
                    return ($0.task.equipment?.name ?? "") < ($1.task.equipment?.name ?? "")
                }

            if entries.isEmpty {
                pdf.paragraph("No scheduled maintenance items.", color: .secondaryLabel)
                return
            }

            let overdue = entries.filter { $0.status == .overdue }.count
            let dueSoon = entries.filter { $0.status == .dueSoon }.count
            pdf.paragraph("\(entries.count) scheduled items — \(overdue) overdue, \(dueSoon) due soon.")

            let columns = [
                PDFColumn("Machine", weight: 0.2),
                PDFColumn("Maintenance Item", weight: 0.24),
                PDFColumn("Status", weight: 0.12),
                PDFColumn("Last Done", weight: 0.14),
                PDFColumn("Next Due", weight: 0.3),
            ]
            let rows = entries.map { entry -> [PDFCell] in
                let task = entry.task
                let unit = task.equipment?.meterType.unitAbbreviation ?? "hrs"
                var lastDone: [String] = []
                if let date = task.lastDoneDate {
                    lastDone.append(date.formatted(date: .numeric, time: .omitted))
                }
                if let meter = task.lastDoneMeter { lastDone.append(meterText(meter, unit: unit)) }
                return [
                    PDFCell(task.equipment?.name ?? "—"),
                    PDFCell(task.name),
                    PDFCell(entry.status.label, color: entry.status.reportColor, bold: true),
                    PDFCell(lastDone.isEmpty ? "Never" : lastDone.joined(separator: " @ ")),
                    PDFCell(task.dueSummary),
                ]
            }
            pdf.table(columns: columns, rows: rows)
        }
    }

    /// Stock levels for every part and fluid, low-stock items flagged in red.
    static func inventory(parts: [Part]) -> URL? {
        let builder = MaintenancePDFBuilder(title: "Parts & Fluids Inventory")
        return builder.render(fileName: "parts-fluids-inventory.pdf") { pdf in
            let lowCount = parts.filter(\.isLowStock).count
            pdf.paragraph("\(parts.count) items in the library — \(lowCount) at or below their low-stock level.")

            for kind in PartKind.allCases {
                let group = parts
                    .filter { $0.kind == kind }
                    .sorted { $0.partDescription < $1.partDescription }
                guard !group.isEmpty else { continue }

                pdf.sectionTitle(kind == .part ? "Parts" : "Fluids")
                let columns = [
                    PDFColumn("Description", weight: 0.28),
                    PDFColumn("OEM #", weight: 0.16),
                    PDFColumn("On Hand", weight: 0.12),
                    PDFColumn("Low At", weight: 0.1),
                    PDFColumn("Supplier", weight: 0.18),
                    PDFColumn("Last Price", weight: 0.16),
                ]
                let rows = group.map { part -> [PDFCell] in
                    let low = part.isLowStock
                    return [
                        PDFCell(part.partDescription),
                        PDFCell(part.oemNumber.isEmpty ? "—" : part.oemNumber),
                        PDFCell(low ? "\(part.stockSummary) ⚠" : part.stockSummary,
                                color: low ? .systemRed : .label, bold: low),
                        PDFCell(part.lowStockThreshold > 0
                                ? part.lowStockThreshold.formatted(.number.precision(.fractionLength(0...1)))
                                : "—"),
                        PDFCell(part.preferredSupplier.isEmpty ? "—" : part.preferredSupplier),
                        PDFCell(money(part.lastPrice)),
                    ]
                }
                pdf.table(columns: columns, rows: rows)
            }
        }
    }

    /// The master parts catalog: identifiers, sourcing, and machine usage.
    static func partsCatalog(parts: [Part]) -> URL? {
        let builder = MaintenancePDFBuilder(title: "Master Parts Catalog")
        return builder.render(fileName: "master-parts-catalog.pdf") { pdf in
            let sorted = parts.sorted { $0.partDescription < $1.partDescription }
            pdf.paragraph("\(sorted.count) parts and fluids in the master library.")

            let columns = [
                PDFColumn("Description", weight: 0.24),
                PDFColumn("OEM #", weight: 0.14),
                PDFColumn("Cross Refs", weight: 0.16),
                PDFColumn("Supplier", weight: 0.14),
                PDFColumn("Price", weight: 0.1),
                PDFColumn("Used On", weight: 0.22),
            ]
            let rows = sorted.map { part -> [PDFCell] in
                [
                    PDFCell(part.partDescription),
                    PDFCell(part.oemNumber.isEmpty ? "—" : part.oemNumber),
                    PDFCell(part.crossRefs.isEmpty ? "—" : part.crossRefs),
                    PDFCell(part.preferredSupplier.isEmpty ? "—" : part.preferredSupplier),
                    PDFCell(money(part.lastPrice)),
                    PDFCell(part.usedOnNames.isEmpty ? "—" : part.usedOnNames.joined(separator: ", ")),
                ]
            }
            pdf.table(columns: columns, rows: rows)
        }
    }
}

// MARK: - Reports screen

/// Wraps a generated report so it can drive a `.sheet(item:)` preview.
private struct GeneratedReport: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct MaintenanceReportsView: View {
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @Query(sort: \Part.partDescription) private var parts: [Part]
    @State private var preview: GeneratedReport?

    var body: some View {
        List {
            Section {
                reportButton("Service Due Report",
                             subtitle: "Every scheduled item across the fleet, worst first",
                             icon: "calendar.badge.exclamationmark") {
                    MaintenanceReports.serviceDue(equipment: equipment)
                }
                reportButton("Parts & Fluids Inventory",
                             subtitle: "Stock levels with low-stock flags",
                             icon: "shippingbox") {
                    MaintenanceReports.inventory(parts: parts)
                }
                reportButton("Master Parts Catalog",
                             subtitle: "OEM numbers, cross refs, suppliers, machine usage",
                             icon: "books.vertical") {
                    MaintenanceReports.partsCatalog(parts: parts)
                }
            } header: {
                Text("Fleet Reports")
            } footer: {
                Text("Reports are formatted for standard letter paper and can be shared or printed from the preview.")
            }

            Section("Machine History") {
                if equipment.isEmpty {
                    Text("No equipment yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(equipment, id: \.uuid) { machine in
                    reportButton(machine.name,
                                 subtitle: "Schedule and complete service history",
                                 icon: machine.category.systemImage) {
                        MaintenanceReports.machineHistory(machine)
                    }
                }
            }
        }
        .navigationTitle("Reports")
        .sheet(item: $preview) { report in
            PDFPreviewSheet(url: report.url, title: report.title)
        }
    }

    private func reportButton(
        _ title: String,
        subtitle: String,
        icon: String,
        generate: @escaping () -> URL?
    ) -> some View {
        Button {
            if let url = generate() {
                preview = GeneratedReport(url: url, title: title)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
            }
        }
    }
}
