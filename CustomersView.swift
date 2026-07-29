import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Model

struct Customer: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var phone = ""
    var email = ""
    var address = ""
    var licenseImage: Data?
    var licenseExpiration: Date?

    var hasLicense: Bool { licenseImage != nil }

    var isLicenseExpired: Bool {
        guard let licenseExpiration else { return false }
        return licenseExpiration < Date()
    }

    /// True when a valid (unexpired) license photo is already on file.
    var hasValidLicense: Bool {
        hasLicense && !isLicenseExpired
    }
}

// MARK: - Storage

enum CustomerStorage {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("customers.json")
    }

    static func load() -> [Customer] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Customer].self, from: data)) ?? []
    }

    static func save(_ customers: [Customer]) {
        guard let data = try? JSONEncoder().encode(customers) else { return }
        try? data.write(to: url, options: [.atomic])
        applyFileProtection(url)
    }

    /// Updates the stored address for the named customer (adding the customer if new),
    /// so address edits made on contracts carry over for future use.
    static func upsertAddress(name: String, address: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAddress.isEmpty else { return }
        var customers = load()
        if let idx = customers.firstIndex(where: { $0.name.compare(trimmedName, options: .caseInsensitive) == .orderedSame }) {
            guard customers[idx].address != trimmedAddress else { return }
            customers[idx].address = trimmedAddress
        } else {
            var customer = Customer()
            customer.name = trimmedName
            customer.address = trimmedAddress
            customers.append(customer)
        }
        save(customers)
    }
}

private func customerDateText(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .omitted)
}

// MARK: - QuickBooks CSV import

/// Parses a QuickBooks (or Excel-exported) customer CSV into `Customer` records.
/// Columns are matched by header name so it tolerates QuickBooks' varying layouts.
enum CustomerCSVImport {
    static func parse(_ rawText: String) -> [Customer] {
        // Strip a leading byte-order mark that Excel often prepends.
        let text = rawText.replacingOccurrences(of: "\u{FEFF}", with: "")
        var rows = parseCSV(text).filter { row in
            !(row.count == 1 && row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        // Disregard the first row and use the second as the header
        guard rows.count > 2 else { return [] }
        _ = rows.removeFirst() // discard row 1
        let header = rows.removeFirst().map { normalize($0) }

        guard let nameIdx = firstIndex(in: header, preferring: [
            "customer full name", "full name", "display name", "customer name", "customer", "name", "company"
        ]) else { return [] }

        let phoneIdx = firstIndex(in: header, containingAny: ["phone", "mobile", "cell"])
        let emailIdx = firstIndex(in: header, containingAny: ["email", "e-mail"])
        let addressIdxs = addressColumns(header)

        var customers: [Customer] = []
        for row in rows {
            func value(_ idx: Int?) -> String {
                guard let idx, idx >= 0, idx < row.count else { return "" }
                return row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let name = value(nameIdx)
            guard !name.isEmpty else { continue }

            var customer = Customer()
            customer.name = name
            customer.phone = cleanPhone(value(phoneIdx))
            customer.email = value(emailIdx)
            customer.address = addressIdxs.map { cleanAddress(value($0)) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            customers.append(customer)
        }
        return customers
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// QuickBooks exports multi-line addresses inside one quoted cell; flatten to one line.
    private static func cleanAddress(_ s: String) -> String {
        s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Strips "Phone:"/"Mobile:" prefixes QuickBooks sometimes includes in the number.
    private static func cleanPhone(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["phone:", "mobile:", "cell:"] where t.lowercased().hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    /// Finds a column, first by exact header match (in priority order), then by substring.
    private static func firstIndex(in header: [String], preferring keys: [String]) -> Int? {
        for key in keys {
            if let idx = header.firstIndex(where: { $0 == key }) { return idx }
        }
        for key in keys {
            if let idx = header.firstIndex(where: { $0.contains(key) }) { return idx }
        }
        return nil
    }

    private static func firstIndex(in header: [String], containingAny keys: [String]) -> Int? {
        for key in keys {
            if let idx = header.firstIndex(where: { $0.contains(key) }) { return idx }
        }
        return nil
    }

    /// Collects address-related columns, preferring billing over shipping, and
    /// assembling separate street/city/state/zip columns when there's no single field.
    private static func addressColumns(_ header: [String]) -> [Int] {
        var result: [Int] = []

        for (idx, h) in header.enumerated() where !h.contains("email") {
            if h.contains("bill") && (h.contains("address") || h.contains("street")) { result.append(idx) }
        }
        if result.isEmpty {
            for (idx, h) in header.enumerated() where !h.contains("email") {
                if h.contains("address") || h.contains("street") { result.append(idx) }
            }
        }

        func addComponent(_ needles: [String]) {
            if let idx = header.firstIndex(where: { h in
                h.contains("bill") && needles.contains(where: { h.contains($0) })
            }) {
                if !result.contains(idx) { result.append(idx) }
            } else if let idx = header.firstIndex(where: { h in
                !h.contains("ship") && needles.contains(where: { h.contains($0) })
            }) {
                if !result.contains(idx) { result.append(idx) }
            }
        }
        addComponent(["city"])
        addComponent(["state", "province"])
        addComponent(["zip", "postal"])
        return result
    }

    /// A minimal RFC-4180 CSV parser: handles quoted fields, escaped quotes, and CRLF.
    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        var iterator = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\r": break
                // "\r\n" is a single Character in Swift, so match it alongside "\n".
                case "\n", "\r\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Customer name autocomplete

/// A name text field that suggests saved customers as you type. Selecting a
/// suggestion sets the name and calls `onSelect` so the caller can fill related fields.
struct CustomerSuggestionField: View {
    let title: String
    @Binding var name: String
    var autocap: TextInputAutocapitalization = .words
    let onSelect: (Customer) -> Void

    @State private var customers: [Customer] = []
    @State private var justSelected = false
    @FocusState private var focused: Bool

    private var matches: [Customer] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return customers
            .filter { !$0.name.isEmpty }
            .filter { $0.name.lowercased().contains(query) && $0.name.lowercased() != query }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        Group {
            LabeledContent(title) {
                TextField("", text: $name)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(autocap)
                    .focused($focused)
            }

            if focused && !justSelected {
                ForEach(matches) { customer in
                    Button {
                        name = customer.name
                        onSelect(customer)
                        justSelected = true
                        focused = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(customer.name)
                                    .foregroundStyle(.primary)
                                if let subtitle = subtitle(for: customer) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.up.left.circle")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .onAppear { customers = CustomerStorage.load() }
        .onChange(of: name) { _, _ in justSelected = false }
    }

    private func subtitle(for customer: Customer) -> String? {
        let parts = [customer.phone, customer.email].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Customers list

struct CustomersView: View {
    @State private var customers: [Customer] = []
    @State private var loaded = false
    @State private var showingImporter = false
    @State private var importSummary: String?
    @State private var showingImportResult = false

    var body: some View {
        Group {
            if customers.isEmpty {
                ContentUnavailableView {
                    Label("No Customers", systemImage: "person.2")
                } description: {
                    Text("Tap + to add a customer, or import your customer list from QuickBooks.")
                } actions: {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from QuickBooks (CSV)", systemImage: "square.and.arrow.down")
                    }
                }
            } else {
                List {
                    ForEach($customers) { $customer in
                        NavigationLink {
                            CustomerDetailView(customer: $customer)
                        } label: {
                            CustomerRow(customer: customer)
                        }
                    }
                    .onDelete { customers.remove(atOffsets: $0) }
                }
            }
        }
        .navigationTitle("Customers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        customers.insert(Customer(), at: 0)
                    } label: {
                        Label("New Customer", systemImage: "plus")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from QuickBooks (CSV)", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .alert("Customer Import", isPresented: $showingImportResult, presenting: importSummary) { _ in
            Button("OK", role: .cancel) {}
        } message: { summary in
            Text(summary)
        }
        .onAppear {
            if !loaded {
                customers = CustomerStorage.load()
                loaded = true
            }
        }
        .onChange(of: customers) { _, newValue in
            CustomerStorage.save(newValue)
        }
    }

    /// Reads the picked CSV file and merges its rows into the customer list,
    /// updating existing customers (matched by name) and adding new ones.
    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? Data(contentsOf: url), let text = Self.decodeText(raw) else {
            importSummary = "Couldn't read that file. Please export it from QuickBooks as a CSV."
            showingImportResult = true
            return
        }

        let imported = CustomerCSVImport.parse(text)
        guard !imported.isEmpty else {
            importSummary = "No customers found. Make sure the file has a header row with a customer/name column."
            showingImportResult = true
            return
        }

        var added = 0
        var updated = 0
        for incoming in imported {
            if let index = customers.firstIndex(where: {
                $0.name.compare(incoming.name, options: .caseInsensitive) == .orderedSame
            }) {
                var existing = customers[index]
                if !incoming.phone.isEmpty { existing.phone = incoming.phone }
                if !incoming.email.isEmpty { existing.email = incoming.email }
                if !incoming.address.isEmpty { existing.address = incoming.address }
                customers[index] = existing
                updated += 1
            } else {
                customers.append(incoming)
                added += 1
            }
        }
        customers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        importSummary = "Imported \(imported.count) row\(imported.count == 1 ? "" : "s") — \(added) added, \(updated) updated."
        showingImportResult = true
    }

    /// Decodes CSV bytes, tolerating the common encodings QuickBooks/Excel produce.
    private static func decodeText(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        return String(data: data, encoding: .isoLatin1)
    }
}

private struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name.isEmpty ? "New Customer" : customer.name)
                    .font(.headline)
                LicenseStatusLabel(customer: customer)
                    .font(.caption)
            }
            Spacer()
        }
    }
}

/// Shows license status: missing, expired (red), or valid (green).
struct LicenseStatusLabel: View {
    let customer: Customer

    var body: some View {
        if !customer.hasLicense {
            Label("No license on file", systemImage: "person.text.rectangle")
                .foregroundStyle(.secondary)
        } else if customer.isLicenseExpired {
            Label("License expired\(expirationSuffix)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if let expiration = customer.licenseExpiration {
            Label("Valid through \(customerDateText(expiration))", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } else {
            Label("On file (no expiration set)", systemImage: "photo")
                .foregroundStyle(.orange)
        }
    }

    private var expirationSuffix: String {
        guard let expiration = customer.licenseExpiration else { return "" }
        return " " + customerDateText(expiration)
    }
}

// MARK: - Customer detail

struct CustomerDetailView: View {
    @Binding var customer: Customer
    @State private var showingPicker = false
    @State private var history: [CustomerHistoryItem] = []

    var body: some View {
        Form {
            Section("Info") {
                LabeledContent("Name") {
                    TextField("Full name", text: $customer.name)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }
                LabeledContent("Phone") {
                    TextField("Phone", text: $customer.phone)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.phonePad)
                }
                LabeledContent("Email") {
                    TextField("Email", text: $customer.email)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                LabeledContent("Address") {
                    TextField("Address", text: $customer.address)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Driver License") {
                if customer.isLicenseExpired {
                    Label("This license is expired — take a new photo.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if customer.hasValidLicense {
                    Label("License on file and valid — no need to re-photograph until it expires.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }

                if let data = customer.licenseImage, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    showingPicker = true
                } label: {
                    Label(customer.hasLicense ? "Retake License Photo" : "Add License Photo",
                          systemImage: "camera")
                }

                Toggle("Expiration date on file", isOn: Binding(
                    get: { customer.licenseExpiration != nil },
                    set: { on in customer.licenseExpiration = on ? (customer.licenseExpiration ?? Date()) : nil }
                ))
                if customer.licenseExpiration != nil {
                    DatePicker("Expiration", selection: Binding(
                        get: { customer.licenseExpiration ?? Date() },
                        set: { customer.licenseExpiration = $0 }
                    ), displayedComponents: .date)
                }

                if customer.hasLicense {
                    Button("Remove License Photo", role: .destructive) {
                        customer.licenseImage = nil
                    }
                }
            }

            historySection
        }
        .navigationTitle(customer.name.isEmpty ? "Customer" : customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            ImageCapturePicker(imageData: $customer.licenseImage)
        }
        .onAppear {
            history = CustomerHistoryLoader.load(for: customer.name)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section {
            if history.isEmpty {
                Text("No jobs on record for this customer yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history) { item in
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: item.icon)
                        }
                        Spacer()
                        Text(currencyString(item.amount))
                            .font(.subheadline.weight(.semibold))
                    }
                }
                LabeledContent("Total Business",
                               value: currencyString(history.reduce(0) { $0 + $1.amount }))
                    .font(.headline)
            }
        } header: {
            Text("History")
        } footer: {
            if !history.isEmpty {
                Text("Rentals, ag services, lumber orders, and milling jobs matched by customer name.")
            }
        }
    }
}

// MARK: - Customer history

/// One past transaction for a customer, from any module.
struct CustomerHistoryItem: Identifiable {
    let id: String
    let date: Date
    let title: String
    let detail: String
    let amount: Double
    let icon: String
}

/// Aggregates every module's records for one customer, matched by
/// case-insensitive name.
enum CustomerHistoryLoader {
    static func load(for name: String) -> [CustomerHistoryItem] {
        let target = normalized(name)
        guard !target.isEmpty else { return [] }
        var items: [CustomerHistoryItem] = []

        for rec in RentalAgreementStorage.loadAll() where normalized(rec.customerName) == target {
            items.append(CustomerHistoryItem(
                id: "rental-\(rec.id)",
                date: rec.data.startDate,
                title: "Rental Agreement",
                detail: rec.data.startDate.formatted(date: .abbreviated, time: .omitted),
                amount: rec.data.subtotal,
                icon: "house.fill"
            ))
        }
        for rec in AgServicesStorage.loadAll() where normalized(rec.customerName) == target {
            items.append(CustomerHistoryItem(
                id: "ag-\(rec.id)",
                date: rec.data.startDate,
                title: "Ag Services",
                detail: rec.data.startDate.formatted(date: .abbreviated, time: .omitted),
                amount: rec.data.estimatedTotal,
                icon: "leaf.fill"
            ))
        }
        for order in OrderStorage.load() where normalized(order.customerName) == target {
            items.append(CustomerHistoryItem(
                id: "order-\(order.id)",
                date: order.createdAt,
                title: "Lumber Order",
                detail: order.createdAt.formatted(date: .abbreviated, time: .omitted),
                amount: order.subtotal,
                icon: "list.bullet.rectangle"
            ))
        }
        for job in MillingJobStorage.loadAll() where normalized(job.customerName) == target {
            items.append(CustomerHistoryItem(
                id: "milling-\(job.id)",
                date: job.date,
                title: "Milling \(job.jobID)\(job.completed ? "" : " (open)")",
                detail: "\(job.totalBF.formatted(.number.precision(.fractionLength(0...2)))) BF · \(job.date.formatted(date: .abbreviated, time: .omitted))",
                amount: job.totalPrice,
                icon: "tree.fill"
            ))
        }

        return items.sorted { $0.date > $1.date }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Customer picker (for pulling a customer into a contract)

struct CustomerPickerSheet: View {
    let onSelect: (Customer) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var customers: [Customer] = []

    var body: some View {
        NavigationStack {
            Group {
                if customers.isEmpty {
                    ContentUnavailableView {
                        Label("No Customers", systemImage: "person.2")
                    } description: {
                        Text("Add customers in the Customers section first.")
                    }
                } else {
                    List(customers) { customer in
                        Button {
                            onSelect(customer)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(customer.name.isEmpty ? "Unnamed" : customer.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                LicenseStatusLabel(customer: customer)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { customers = CustomerStorage.load() }
        }
    }
}

// MARK: - Image capture (camera, falling back to photo library)

struct ImageCapturePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImageCapturePicker
        init(_ parent: ImageCapturePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.imageData = image.jpegData(compressionQuality: 0.8)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

