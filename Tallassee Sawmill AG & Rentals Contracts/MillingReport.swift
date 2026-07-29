//
//  MillingReport.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Customer-facing PDF for a completed milling job: business and customer
//  details, every board with its dimensions and board feet, and totals.
//  Uses the shared MaintenancePDFBuilder for the letter-size layout with
//  logo, date, and page numbers.
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

            pdf.sectionTitle("Boards")
            let columns = [
                PDFColumn("Board #", weight: 0.1),
                PDFColumn("Species", weight: 0.22),
                PDFColumn("Width (in)", weight: 0.16),
                PDFColumn("Thickness (in)", weight: 0.18),
                PDFColumn("Length (ft)", weight: 0.14),
                PDFColumn("Board Feet", weight: 0.2),
            ]
            pdf.table(columns: columns, rows: boardRows(for: job))

            pdf.sectionTitle("Totals")
            pdf.infoLine("Total Boards", "\(job.totalPieces)")
            pdf.infoLine("Total Board Feet",
                         job.totalBF.formatted(.number.precision(.fractionLength(0...2))))
            pdf.infoLine("Milling Total", currencyString(job.totalPrice))
        }
    }

    /// Expands each job line into individually numbered boards, so a line of
    /// "qty 5" becomes boards 1–5 with the same dimensions.
    private static func boardRows(for job: MillingJob) -> [[PDFCell]] {
        var rows: [[PDFCell]] = []
        var boardNumber = 0
        for line in job.lines {
            let quantity = max(Int(line.quantity.filter { $0.isNumber }) ?? 0, 0)
            let boardFeet = line.bfPerPiece.formatted(.number.precision(.fractionLength(0...2)))
            for _ in 0..<quantity {
                boardNumber += 1
                rows.append([
                    PDFCell("\(boardNumber)"),
                    PDFCell(line.species.displayName),
                    PDFCell(line.widthIn),
                    PDFCell(line.thicknessIn),
                    PDFCell(line.lengthFt),
                    PDFCell(boardFeet),
                ])
            }
        }
        return rows
    }
}
