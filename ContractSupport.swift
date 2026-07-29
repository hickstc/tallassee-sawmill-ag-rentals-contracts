import SwiftUI
import UIKit
import PDFKit

// Applies strongest on-device protection to a file (accessible only when unlocked).
func applyFileProtection(_ url: URL) {
    do {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    } catch {
        // Non-fatal: if protection can't be set, continue normally.
    }
}

// MARK: - Payment method

/// How the customer pays. Credit card adds a 3% non-taxable surcharge.
enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case cash = "Cash"
    case check = "Check"
    case card = "Credit Card"

    var id: String { rawValue }
}

// MARK: - Shared business info + HTML styling

enum ContractHTML {
    static let providerName = "Tallassee Sawmill, AG & Rental Services"
    static let providerAddress = "871 County Rd. 77, Tallassee, AL 36078"
    static let providerPhone = "334-524-3601"

    static let css = """
    <style>
      * { -webkit-print-color-adjust: exact; }
      body { font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 11px; color: #111; line-height: 1.38; margin: 0; }
      h1 { font-size: 19px; margin: 0 0 2px 0; }
      .sub { font-size: 12px; font-weight: bold; color: #555; margin: 0 0 14px 0; }
      h2 { font-size: 12px; margin: 15px 0 4px 0; page-break-after: avoid; }
      p { margin: 0 0 7px 0; }
      .field { margin: 0 0 3px 0; }
      .muted { color: #666; font-size: 9px; }
      .hr { border-top: 1px solid #ccc; margin: 14px 0; }
      .sig { height: 55px; }
      .header { margin-bottom: 12px; }
    </style>
    """

    /// Wraps a body fragment in a full HTML document.
    static func page(_ body: String) -> String {
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\">\(css)</head><body>\(body)</body></html>"
    }

    /// A labeled fill-in line. `valueHTML` must already be HTML-ready (escaped or an <img>).
    static func field(_ label: String, _ valueHTML: String) -> String {
        "<div class=\"field\"><b>\(label)</b> \(valueHTML)</div>"
    }
}

// MARK: - HTML helpers

func htmlEscape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

/// Escaped value, or an underscore blank when empty.
func fieldValue(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "________________________" : htmlEscape(trimmed)
}

/// Multiline escaped text with line breaks preserved, or a blank line.
func multilineValue(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "________________________________________" }
    return htmlEscape(trimmed).replacingOccurrences(of: "\n", with: "<br>")
}

/// The signature line placeholder. The actual signature image is stamped onto the
/// PDF after rendering (see `renderContractPDF`) because the HTML formatter does not
/// reliably render embedded base64 images.
func signatureHTML(_ data: Data?) -> String {
    "________________________"
}

func money(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "$____________" }
    return htmlEscape(trimmed.hasPrefix("$") ? trimmed : "$\(trimmed)")
}

func longDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    return formatter.string(from: date)
}

func dateTimeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func safeFileStem(_ name: String, fallback: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return fallback }
    let cleaned = trimmed.replacingOccurrences(of: " ", with: "_")
        .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    return cleaned.isEmpty ? fallback : cleaned
}

/// Parses a user-entered amount, ignoring currency symbols and stray characters.
func parseAmount(_ text: String) -> Double {
    Double(text.filter { $0.isNumber || $0 == "." }) ?? 0
}

func currencyString(_ value: Double) -> String {
    value.formatted(.currency(code: "USD"))
}

// MARK: - HTML → PDF renderer (auto-paginates, supports images)

enum HTMLPDF {
    static func render(_ html: String, fileName: String) -> URL? {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let pageSize = CGSize(width: 612, height: 792) // US Letter @ 72dpi
        let paperRect = CGRect(origin: .zero, size: pageSize)
        let printableRect = paperRect.insetBy(dx: 40, dy: 48)
        renderer.setValue(paperRect, forKey: "paperRect")
        renderer.setValue(printableRect, forKey: "printableRect")

        let pageCount = max(renderer.numberOfPages, 1)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paperRect, nil)
        for page in 0..<pageCount {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: paperRect)
        }
        UIGraphicsEndPDFContext()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            applyFileProtection(url)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Contract PDF with stamped signature

/// Renders the contract HTML to PDF, then stamps the signature image onto the
/// signature line (found by its label) so it appears reliably on the page.
func renderContractPDF(html: String, fileName: String, signature: Data?, signatureLabel: String) -> URL? {
    guard let baseURL = HTMLPDF.render(html, fileName: "base-\(fileName)") else { return nil }
    guard let signature, !signature.isEmpty, let image = UIImage(data: signature) else {
        applyFileProtection(baseURL)
        return baseURL
    }
    let out = SignatureStamper.stamp(pdfAt: baseURL, image: image, afterLabel: signatureLabel, outputFileName: fileName) ?? baseURL
    applyFileProtection(out)
    return out
}

/// Draws a signature image onto an existing PDF, positioned just after a text label.
enum SignatureStamper {
    static func stamp(pdfAt url: URL, image: UIImage, afterLabel label: String, outputFileName: String) -> URL? {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        let matches = document.findString(label, withOptions: [.caseInsensitive])
        guard let selection = matches.last, let targetPage = selection.pages.last else { return url }
        let targetIndex = document.index(for: targetPage)
        let labelBounds = selection.bounds(for: targetPage)

        let pageBounds = document.page(at: 0)?.bounds(for: .mediaBox)
            ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)

        do {
            let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
            try renderer.writePDF(to: outURL) { ctx in
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    ctx.beginPage()
                    let cg = ctx.cgContext
                    cg.saveGState()
                    // Flip into PDF (bottom-left origin) coordinates to draw the page + image.
                    cg.translateBy(x: 0, y: bounds.height)
                    cg.scaleBy(x: 1, y: -1)
                    page.draw(with: .mediaBox, to: cg)
                    if index == targetIndex, let cgImage = image.cgImage {
                        let height = max(labelBounds.height * 1.9, 26)
                        let rect = CGRect(x: labelBounds.maxX + 8,
                                          y: labelBounds.minY,
                                          width: 190,
                                          height: height)
                        cg.draw(cgImage, in: rect)
                    }
                    cg.restoreGState()
                }
            }
            applyFileProtection(outURL)
            return outURL
        } catch {
            return url
        }
    }
}

// MARK: - Signature capture

/// A finger-drawn signature pad that writes a PNG into `imageData`.
struct SignaturePad: View {
    @Binding var imageData: Data?

    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.white
                if strokes.isEmpty && current.isEmpty, let data = imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else if strokes.isEmpty && current.isEmpty {
                    Text("Sign here")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
                Canvas { context, _ in
                    var all = strokes
                    if !current.isEmpty { all.append(current) }
                    for stroke in all {
                        guard let first = stroke.first else { continue }
                        var path = Path()
                        path.move(to: first)
                        for point in stroke.dropFirst() { path.addLine(to: point) }
                        context.stroke(path, with: .color(.black),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { canvasSize = geo.size }
                            .onChange(of: geo.size) { _, newValue in canvasSize = newValue }
                    }
                )
            }
            .frame(height: 160)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.5)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in current.append(value.location) }
                    .onEnded { _ in
                        if !current.isEmpty { strokes.append(current); current = [] }
                        rasterize()
                    }
            )

            Button(role: .destructive) {
                strokes = []
                current = []
                imageData = nil
            } label: {
                Label("Clear Signature", systemImage: "trash")
            }
            .font(.callout)
        }
    }

    private func rasterize() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false   // transparent background so it stamps cleanly onto the PDF
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let image = renderer.image { _ in
            UIColor.black.setStroke()
            let path = UIBezierPath()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                path.move(to: first)
                for point in stroke.dropFirst() { path.addLine(to: point) }
            }
            path.stroke()
        }
        imageData = image.pngData()
    }
}
