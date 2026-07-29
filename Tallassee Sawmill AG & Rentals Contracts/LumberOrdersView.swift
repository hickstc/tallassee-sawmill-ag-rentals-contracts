import SwiftUI
import Foundation
import UIKit
import CoreText

// MARK: - Models

/// Wood species offered, mirroring the website pricing calculator.
enum WoodSpecies: String, CaseIterable, Identifiable, Codable, Hashable {
    case pine
    case cypress
    case cedar
    case whiteOak
    case redOak
    case hickory
    case poplar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pine: return "Pine"
        case .cypress: return "Cypress"
        case .cedar: return "Cedar"
        case .whiteOak: return "White Oak"
        case .redOak: return "Red Oak"
        case .hickory: return "Hickory"
        case .poplar: return "Poplar"
        }
    }

    var isPine: Bool { self == .pine }

    /// Flat $/board-foot rate for species sold true/full size only. `nil` for Pine (which uses size bands).
    var flatRate: Double? {
        switch self {
        case .pine: return nil
        case .cypress: return 4.50
        case .cedar: return 4.00
        case .whiteOak: return 3.74
        case .redOak: return 3.00
        case .hickory: return 3.00
        case .poplar: return 1.85
        }
    }
}

/// How a Pine size is entered. Non-Pine species are always true size.
enum SizeType: String, CaseIterable, Identifiable, Codable, Hashable {
    case nominal   // "Common size" — big-box lumber labeled 2x6 but planed to 1.5x5.5
    case trueSize  // Full / true rough-cut sawmill size

    var id: String { rawValue }
}

/// A single line of lumber the customer wants cut.
struct CutLine: Identifiable, Codable, Hashable {
    var id = UUID()
    var species: WoodSpecies = .pine
    var sizeType: SizeType = .nominal
    var thicknessIn: String = "2"
    var widthIn: String = "6"
    var lengthFt: String = "12"
    var quantity: String = "1"
}

/// A saved customer order.
struct LumberOrder: Identifiable, Codable, Hashable {
    var id = UUID()
    var customerName: String = ""
    var createdAt: Date = Date()
    var lines: [CutLine] = []

    var subtotal: Double {
        lines.reduce(0) { $0 + SawmillPricing.evaluate($1).total }
    }
    func salesTax(percent: Double) -> Double { subtotal * percent / 100 }
    func grandTotal(percent: Double) -> Double { subtotal + salesTax(percent: percent) }
}

// MARK: - Pricing engine (ported from the website calculator)

enum SawmillPricing {
    static let defaultPineRate = 1.35

    struct PineBand {
        let label: String
        let minWidth: Double
        let maxWidth: Double
        let thickMax: Double
        let rate: Double
    }

    /// Pine rate bands — $/board foot by true thickness ceiling and width range.
    static let pineBands: [PineBand] = [
        PineBand(label: "1\" boards, up to 8\" wide",        minWidth: 0.5,   maxWidth: 8,  thickMax: 1.1, rate: 1.20),
        PineBand(label: "1\" boards, 9\"+ wide",             minWidth: 8.01,  maxWidth: 99, thickMax: 1.1, rate: 1.25),
        PineBand(label: "2\" (1.5\" true), up to 4\" wide",  minWidth: 0.5,   maxWidth: 4,  thickMax: 2.1, rate: 0.90),
        PineBand(label: "2\" (1.5\" true), 5\"–10\" wide",   minWidth: 4.01,  maxWidth: 10, thickMax: 2.1, rate: 1.00),
        PineBand(label: "2\" (1.5\" true), 11\"+ wide",      minWidth: 10.01, maxWidth: 99, thickMax: 2.1, rate: 1.55),
        PineBand(label: "4\" (3.5\" true), up to 8\" wide",  minWidth: 0.5,   maxWidth: 8,  thickMax: 4.1, rate: 1.20),
        PineBand(label: "4\" (3.5\" true), 9\"+ wide",       minWidth: 8.01,  maxWidth: 99, thickMax: 4.1, rate: 1.35),
        PineBand(label: "6x6 timbers",                       minWidth: 5.0,   maxWidth: 6.0,  thickMax: 6.1, rate: 1.00),
        PineBand(label: "6x8 timbers",                       minWidth: 6.01,  maxWidth: 8.0,  thickMax: 6.1, rate: 1.20),
        PineBand(label: "6x10 timbers",                      minWidth: 8.01,  maxWidth: 10.0, thickMax: 6.1, rate: 1.25),
        PineBand(label: "6x12 timbers",                      minWidth: 10.01, maxWidth: 12.0, thickMax: 6.1, rate: 1.30),
    ]

    /// Standard nominal → true size conversion for dimensional Pine. Other values pass through unchanged.
    static let nominalToTrue: [Double: Double] = [
        1: 0.75, 2: 1.5, 3: 2.5, 4: 3.5, 6: 5.5, 8: 7.25, 10: 9.25, 12: 11.25
    ]

    static func toTrue(_ n: Double) -> Double { nominalToTrue[n] ?? n }

    /// Parse a user-entered numeric string, ignoring stray characters.
    static func number(_ text: String) -> Double {
        Double(text.filter { $0.isNumber || $0 == "." }) ?? 0
    }

    struct Evaluation {
        var bfPerPiece: Double
        var quantity: Int
        var rate: Double
        var total: Double
        var rateLabel: String
        /// True thickness/width actually used for pricing (after any nominal conversion).
        var trueThickness: Double
        var trueWidth: Double
    }

    static func evaluate(_ line: CutLine) -> Evaluation {
        let useNominal = line.species.isPine && line.sizeType == .nominal
        var t = number(line.thicknessIn)
        var w = number(line.widthIn)
        let l = number(line.lengthFt)

        // Quantity: matches the site (blank/zero/invalid falls back to 1).
        let qParsed = Int(line.quantity.filter { $0.isNumber }) ?? 0
        let q = qParsed <= 0 ? 1 : qParsed

        if useNominal {
            t = toTrue(t)
            w = toTrue(w)
        }

        let bf = (t * w * l) / 12.0
        guard bf > 0 else {
            return Evaluation(bfPerPiece: 0, quantity: q, rate: 0, total: 0,
                              rateLabel: "—", trueThickness: t, trueWidth: w)
        }

        let pricing = LumberPricing.current
        let rate: Double
        let label: String
        if line.species.isPine {
            if let match = pineBands.enumerated()
                .filter({ w >= $0.element.minWidth && w <= $0.element.maxWidth && t <= $0.element.thickMax })
                .sorted(by: { $0.element.thickMax < $1.element.thickMax })
                .first {
                rate = pricing.pineBandRate(at: match.offset)
                label = "\(match.element.label) · \(fmtRate(rate))/BF"
            } else {
                rate = pricing.defaultPineRate
                label = "No standard size match · \(fmtRate(rate))/BF (default)"
            }
        } else {
            rate = pricing.flatRate(for: line.species)
            label = "\(line.species.displayName) · \(fmtRate(rate))/BF"
        }

        let total = bf * rate * Double(q)
        return Evaluation(bfPerPiece: bf, quantity: q, rate: rate, total: total,
                          rateLabel: label, trueThickness: t, trueWidth: w)
    }

    private static func fmtRate(_ value: Double) -> String {
        "$" + String(format: "%.2f", value)
    }
}

// MARK: - Persistence

enum OrderStorage {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("lumber_orders.json")
    }

    static func load() -> [LumberOrder] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([LumberOrder].self, from: data)) ?? []
    }

    static func save(_ orders: [LumberOrder]) {
        guard let data = try? JSONEncoder().encode(orders) else { return }
        try? data.write(to: url, options: [.atomic])
        applyFileProtection(url)
    }
}

// MARK: - Formatting helpers

private func currency(_ value: Double) -> String {
    value.formatted(.currency(code: "USD"))
}

private func boardFeetText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
}

// MARK: - Orders list

struct LumberOrdersView: View {
    @State private var orders: [LumberOrder] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if orders.isEmpty {
                ContentUnavailableView {
                    Label("No Orders", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Tap + to start an order for a customer.")
                }
            } else {
                List {
                    ForEach($orders) { $order in
                        NavigationLink {
                            OrderDetailView(order: $order)
                        } label: {
                            OrderRow(order: order)
                        }
                    }
                    .onDelete { orders.remove(atOffsets: $0) }
                }
            }
        }
        .navigationTitle("Lumber Orders")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    orders.insert(LumberOrder(), at: 0)
                } label: {
                    Label("New Order", systemImage: "plus")
                }
            }
        }
        .onAppear {
            if !loaded {
                orders = OrderStorage.load()
                loaded = true
            }
        }
        .onChange(of: orders) { _, newValue in
            OrderStorage.save(newValue)
        }
    }
}

private struct OrderRow: View {
    let order: LumberOrder
    @AppStorage("salesTaxPercent") private var taxPercent: Double = 6.5

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(order.customerName.isEmpty ? "New Customer" : order.customerName)
                    .font(.headline)
                Text("\(order.lines.count) cut\(order.lines.count == 1 ? "" : "s") · \(order.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(currency(order.grandTotal(percent: taxPercent)))
                .font(.subheadline.weight(.semibold))
        }
    }
}

// MARK: - Order detail

struct OrderDetailView: View {
    @Binding var order: LumberOrder
    @AppStorage("salesTaxPercent") private var taxPercent: Double = 6.5
    @State private var draft = CutLine()
    @State private var shareItem: ShareItem?

    var body: some View {
        Form {
            Section("Customer") {
                CustomerSuggestionField(title: "Customer", name: $order.customerName) { picked in
                    // Only name is stored on the order for now; you could show contact info below if desired.
                    order.customerName = picked.name
                }
            }

            Section("Add Cut") {
                CutFields(line: $draft)

                let preview = SawmillPricing.evaluate(draft)
                LabeledContent {
                    Text(currency(preview.total)).font(.headline)
                } label: {
                    Text(preview.rateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    order.lines.append(draft)
                    draft = CutLine()
                } label: {
                    Label("Add to Order", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview.bfPerPiece <= 0)
            }

            Section("Cuts") {
                if order.lines.isEmpty {
                    Text("No cuts yet.").foregroundStyle(.secondary)
                } else {
                    ForEach($order.lines) { $line in
                        NavigationLink {
                            EditCutView(line: $line)
                        } label: {
                            CutRow(line: line)
                        }
                    }
                    .onDelete { order.lines.remove(atOffsets: $0) }
                }
            }

            Section("Total") {
                LabeledContent("Subtotal", value: currency(order.subtotal))
                HStack {
                    Text("Sales Tax")
                    Spacer()
                    TextField("6.5", value: $taxPercent, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 60)
                    Text("%")
                }
                LabeledContent("Tax", value: currency(order.salesTax(percent: taxPercent)))
                LabeledContent("Total", value: currency(order.grandTotal(percent: taxPercent)))
                    .font(.headline)
            }
        }
        .navigationTitle(order.customerName.isEmpty ? "New Order" : order.customerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        if let url = makeQuotePDF() { shareItem = ShareItem(url: url) }
                    } label: {
                        Label("Share Quote (PDF)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        if let url = makeQuotePDF() { PrintService.present(url) }
                    } label: {
                        Label("Print Quote", systemImage: "printer")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(order.lines.isEmpty)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
    }

    private func makeQuotePDF() -> URL? {
        let base = order.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = base.isEmpty ? "Lumber-Quote" : "Quote-" + base.replacingOccurrences(of: " ", with: "_")
        return PDFRenderer.write(QuoteDocument.attributed(for: order, taxPercent: taxPercent), fileName: "\(name).pdf")
    }
}

/// Full-screen editor for an existing cut line.
private struct EditCutView: View {
    @Binding var line: CutLine

    var body: some View {
        Form {
            Section("Cut") {
                CutFields(line: $line)
            }
            Section("Price") {
                let ev = SawmillPricing.evaluate(line)
                LabeledContent("Board feet (each)", value: boardFeetText(ev.bfPerPiece))
                LabeledContent("Rate", value: ev.rateLabel)
                LabeledContent("Line total", value: currency(ev.total))
                    .font(.headline)
            }
        }
        .navigationTitle("Edit Cut")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
    }
}

/// Shared field set used for both adding and editing a cut.
struct CutFields: View {
    @Binding var line: CutLine

    var body: some View {
        Picker("Species", selection: $line.species) {
            ForEach(WoodSpecies.allCases) { species in
                Text(species.displayName).tag(species)
            }
        }

        if line.species.isPine {
            Picker("Size", selection: $line.sizeType) {
                Text("Common").tag(SizeType.nominal)
                Text("Full / true").tag(SizeType.trueSize)
            }
            .pickerStyle(.segmented)
            Text(line.sizeType == .nominal
                 ? "Common: labeled size (a 2×6 is priced as a true 1.5×5.5)."
                 : "Full/true: rough-cut sawmill size (a 2×6 is a true 2×6).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(line.species.displayName) is priced at full/true size, flat rate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        numericRow("Thickness (in)", text: $line.thicknessIn)
        numericRow("Width (in)", text: $line.widthIn)
        numericRow("Length (ft)", text: $line.lengthFt)
        numericRow("Quantity", text: $line.quantity, keyboard: .numberPad)
    }

    private func numericRow(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .decimalPad) -> some View {
        LabeledContent(label) {
            SelectAllTextField(placeholder: "0", text: text, keyboard: keyboard)
                .frame(maxWidth: 120)
        }
    }
}

/// A UIKit-backed text field that selects (highlights) its current contents when
/// tapped, so the existing value can be typed over immediately.
struct SelectAllTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .decimalPad

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.textAlignment = .right
        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.editingChanged(_:)),
                        for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
        uiView.keyboardType = keyboard
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }

        @objc func editingChanged(_ field: UITextField) {
            text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            // Defer so the selection sticks after the field becomes first responder.
            DispatchQueue.main.async {
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument,
                                                          to: field.endOfDocument)
            }
        }
    }
}

private struct CutRow: View {
    let line: CutLine

    var body: some View {
        let ev = SawmillPricing.evaluate(line)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(descriptor)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(currency(ev.total))
                    .font(.subheadline.weight(.semibold))
            }
            Text("\(boardFeetText(ev.bfPerPiece)) BF each · \(ev.rateLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var descriptor: String {
        let t = line.thicknessIn.isEmpty ? "?" : line.thicknessIn
        let w = line.widthIn.isEmpty ? "?" : line.widthIn
        let l = line.lengthFt.isEmpty ? "?" : line.lengthFt
        let q = SawmillPricing.evaluate(line).quantity
        return "\(line.species.displayName) \(t)×\(w)×\(l)ft × \(q)"
    }
}

// MARK: - Keyboard

private func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil, from: nil, for: nil
    )
}

// MARK: - PDF / Share / Print (shared across the app)

/// Identifiable wrapper so a URL can drive a `.sheet(item:)`.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Wraps `UIActivityViewController` for SwiftUI share sheets.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Presents the system print dialog for a PDF file.
enum PrintService {
    static func present(_ url: URL) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = url.deletingPathExtension().lastPathComponent
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true, completionHandler: nil)
    }
}

/// Renders an attributed string to a multi-page US-Letter PDF using Core Text pagination.
enum PDFRenderer {
    static func write(_ attributed: NSAttributedString, fileName: String) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72dpi
        let margin: CGFloat = 48
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        do {
            try renderer.writePDF(to: url) { ctx in
                var position = 0
                let total = attributed.length
                repeat {
                    ctx.beginPage()
                    let cg = ctx.cgContext
                    cg.textMatrix = .identity
                    cg.translateBy(x: 0, y: pageRect.height)
                    cg.scaleBy(x: 1, y: -1)

                    let textRect = CGRect(x: margin, y: margin,
                                          width: pageRect.width - margin * 2,
                                          height: pageRect.height - margin * 2)
                    let path = CGPath(rect: textRect, transform: nil)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: position, length: 0), path, nil)
                    CTFrameDraw(frame, cg)

                    let visible = CTFrameGetVisibleStringRange(frame)
                    if visible.length == 0 { break }
                    position += visible.length
                } while position < total
            }
            applyFileProtection(url)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Quote document

/// Builds the printable/shareable lumber quote as styled text.
enum QuoteDocument {
    static func attributed(for order: LumberOrder, taxPercent: Double) -> NSAttributedString {
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

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        append("Tallassee Sawmill, AG & Rental Services", font: .boldSystemFont(ofSize: 18), spacingAfter: 2)
        append("871 County Rd. 77, Tallassee, AL 36078  ·  334-524-3601",
               font: .systemFont(ofSize: 10), spacingAfter: 16, color: .darkGray)

        append("Lumber Quote", font: .boldSystemFont(ofSize: 15), spacingAfter: 8)
        append("Customer:  \(order.customerName.isEmpty ? "—" : order.customerName)",
               font: .systemFont(ofSize: 12), spacingAfter: 2)
        append("Date:  \(dateFormatter.string(from: order.createdAt))",
               font: .systemFont(ofSize: 12), spacingAfter: 14)

        if order.lines.isEmpty {
            append("(No cuts on this order)", font: .italicSystemFont(ofSize: 12), spacingAfter: 10, color: .gray)
        } else {
            for line in order.lines {
                let ev = SawmillPricing.evaluate(line)
                append("\(ev.quantity)×  \(line.species.displayName)  \(line.thicknessIn)×\(line.widthIn)×\(line.lengthFt) ft        \(currency(ev.total))",
                       font: .systemFont(ofSize: 12), spacingAfter: 1)
                append("      \(boardFeetText(ev.bfPerPiece)) BF each · \(ev.rateLabel)",
                       font: .systemFont(ofSize: 10), spacingAfter: 9, color: .darkGray)
            }
        }

        append("Subtotal:  \(currency(order.subtotal))", font: .systemFont(ofSize: 12), spacingAfter: 2)
        append("Sales Tax (\(String(format: "%g", taxPercent))%):  \(currency(order.salesTax(percent: taxPercent)))", font: .systemFont(ofSize: 12), spacingAfter: 2)
        append("Total:  \(currency(order.grandTotal(percent: taxPercent)))", font: .boldSystemFont(ofSize: 15), spacingAfter: 16)

        append("This is an estimate. Final pricing confirmed at time of order.",
               font: .italicSystemFont(ofSize: 9), color: .gray)

        return doc
    }
}

