//
//  MillingReport.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Customer-facing PDF for a completed milling job: business and customer
//  details, one row per board size milled (with quantity and board feet),
//  and totals. Uses the shared MaintenancePDFBuilder for the letter-size
//  layout with logo, date, and page numbers.
//

import Foundation
import UIKit

@MainActor
enum MillingReport {

    static let businessName = "Tallassee Sawmill AG & Rentals"

    /// Renders the customer lumber report and returns the PDF's URL.
    static func customerLumberReport(for job: MillingJob) -> URL? {
        let builder = MaintenancePDFBuilder(title: "Customer Lumber Report")
        let stem = safeFileStem(job.customerName, fallback: "Milling-Job")
        return builder.render(fileName: "\(stem)-\(job.jobID)-lumber-report.pdf") { pdf in
            pdf.sectionTitle("Job")
            pdf.infoLine("Business", businessName)
            pdf.infoLine("Customer", job.customerName.isEmpty ? "—" : job.customerName)
            pdf.infoLine("Job ID", job.jobID)
            pdf.infoLine("Date", job.date.formatted(date: .long, time: .omitted))
            if !job.notes.isEmpty {
                pdf.infoLine("Notes", job.notes)
            }

            pdf.sectionTitle("Lumber Milled")
            let columns = [
                PDFColumn("Qty", weight: 0.09),
                PDFColumn("Species", weight: 0.2),
                PDFColumn("Thickness (in)", weight: 0.17),
                PDFColumn("Width (in)", weight: 0.14),
                PDFColumn("Length (ft)", weight: 0.14),
                PDFColumn("BF / Board", weight: 0.13),
                PDFColumn("Total BF", weight: 0.13),
            ]
            pdf.table(columns: columns, rows: sizeRows(for: job))

            pdf.sectionTitle("Totals")
            pdf.infoLine("Total Boards", "\(job.totalPieces)")
            pdf.infoLine("Total Board Feet",
                         job.totalBF.formatted(.number.precision(.fractionLength(0...2))))
            if job.mobilizationTotal > 0 {
                pdf.infoLine("Milling Subtotal", currencyString(job.millingSubtotal))
                if job.sawmillMobilization {
                    pdf.infoLine("Sawmill Mobilization Fee",
                                 currencyString(MillingJob.mobilizationFee))
                }
                if job.skidSteerMobilization {
                    pdf.infoLine("Skid Steer Mobilization Fee",
                                 currencyString(MillingJob.mobilizationFee))
                }
            }
            pdf.infoLine("Total", currencyString(job.totalPrice))
        }
    }

    /// One row per distinct board size: lines with the same species and
    /// dimensions are combined, with quantities and board feet summed.
    private static func sizeRows(for job: MillingJob) -> [[PDFCell]] {
        struct SizeKey: Hashable {
            let species: String
            let thickness: String
            let width: String
            let length: String
        }
        struct SizeTotals {
            var quantity = 0
            var bfPerPiece = 0.0
            var totalBF = 0.0
            var firstIndex = 0
        }

        var totals: [SizeKey: SizeTotals] = [:]
        for (index, line) in job.lines.enumerated() {
            let key = SizeKey(species: line.species.displayName,
                              thickness: line.thicknessIn,
                              width: line.widthIn,
                              length: line.lengthFt)
            var entry = totals[key] ?? SizeTotals(firstIndex: index)
            entry.quantity += max(Int(line.quantity.filter { $0.isNumber }) ?? 0, 0)
            entry.bfPerPiece = line.bfPerPiece
            entry.totalBF += line.totalBF
            totals[key] = entry
        }

        // Keep sizes in the order they were first entered.
        return totals
            .sorted { $0.value.firstIndex < $1.value.firstIndex }
            .map { key, entry in
                [
                    PDFCell("\(entry.quantity)"),
                    PDFCell(key.species),
                    PDFCell(key.thickness),
                    PDFCell(key.width),
                    PDFCell(key.length),
                    PDFCell(entry.bfPerPiece.formatted(.number.precision(.fractionLength(0...2)))),
                    PDFCell(entry.totalBF.formatted(.number.precision(.fractionLength(0...2)))),
                ]
            }
    }
}
