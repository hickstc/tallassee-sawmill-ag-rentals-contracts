import SwiftUI

// MARK: - Model

enum DamageWaiverChoice: String, Codable, CaseIterable, Identifiable {
    case accepted
    case declined
    var id: String { rawValue }
    var label: String { self == .accepted ? "Accepted" : "Declined" }
}

/// One rented item on an agreement (equipment + tier + rate + quantity).
struct RentalLineItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var itemName = ""
    var tierLabel = ""
    var rate = ""
    var quantity = "1"

    var rateAmount: Double { parseAmount(rate) }
    var quantityValue: Int { max(1, Int(quantity.filter { $0.isNumber }) ?? 1) }
    var lineTotal: Double { rateAmount * Double(quantityValue) }
    var displayName: String {
        if itemName.trimmingCharacters(in: .whitespaces).isEmpty { return "Item" }
        return tierLabel.isEmpty ? itemName : "\(itemName) — \(tierLabel)"
    }
}

struct RentalAgreementData: Codable, Equatable {
    var lesseeName = ""
    var mailingAddress = ""
    var items: [RentalLineItem] = []
    var startDate = Date()
    var returnDate = Date()
    var deposit = ""
    var pickupLocation = ""
    var paymentTerms = "Due upon pickup"
    var damageWaiver: DamageWaiverChoice = .accepted
    var signatureData: Data?
    var licenseImage: Data?
    var licenseExpiration: Date?
    // Stored as an optional raw value so agreements saved before this field existed still decode.
    var paymentMethodRaw: String?

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw ?? "") ?? .cash }
        set { paymentMethodRaw = newValue.rawValue }
    }

    var hasLicense: Bool { licenseImage != nil }
    var isLicenseExpired: Bool {
        guard let licenseExpiration else { return false }
        return licenseExpiration < Date()
    }

    var subtotal: Double { items.reduce(0) { $0 + $1.lineTotal } }
    /// 10% of the rental charges when the damage waiver is accepted; not taxed.
    var damageWaiverFee: Double { damageWaiver == .accepted ? subtotal * 0.10 : 0 }
    /// Sales tax applies to the rental subtotal only.
    func tax(percent: Double) -> Double { subtotal * percent / 100 }
    /// 3% surcharge on the full amount charged when paying by card; not taxed.
    func creditCardFee(percent: Double) -> Double {
        paymentMethod == .card ? (subtotal + damageWaiverFee + tax(percent: percent)) * 0.03 : 0
    }
    func totalWithTax(percent: Double) -> Double {
        subtotal + damageWaiverFee + tax(percent: percent) + creditCardFee(percent: percent)
    }
}

// MARK: - View

struct RentalAgreementView: View {
    @AppStorage("salesTaxPercent") private var taxPercent: Double = 6.5
    @Environment(\.scenePhase) private var scenePhase
    @State private var data = RentalAgreementData()
    @State private var catalog: [RentalItem] = []
    @State private var shareItem: ShareItem?
    @State private var showingReview = false
    @State private var showingLicensePicker = false
    @State private var showingCustomerPicker = false
    @State private var showingLicenseScanner = false
    @State private var scanImageData: Data?
    @State private var showingScanResult = false
    @State private var scanMessage = ""

    @State private var showingSaves = false
    @State private var records: [RentalAgreementRecord] = []
    @State private var currentRecord: RentalAgreementRecord?

    var body: some View {
        Form {
            Section {
                Button {
                    showingReview = true
                } label: {
                    Label("Review Full Agreement", systemImage: "doc.text.magnifyingglass")
                }
            } footer: {
                Text("Open the complete contract full screen to read and sign.")
            }

            Section("Rental Info") {
                CustomerSuggestionField(title: "Lessee", name: $data.lesseeName) { picked in
                    if picked.licenseImage != nil { data.licenseImage = picked.licenseImage }
                    if picked.licenseExpiration != nil { data.licenseExpiration = picked.licenseExpiration }
                    if !picked.address.isEmpty { data.mailingAddress = picked.address }
                }
                LabeledContent("Address") {
                    TextField("Mailing address", text: $data.mailingAddress)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Start", selection: $data.startDate)
                DatePicker("Return", selection: $data.returnDate)
                LabeledContent("Deposit") {
                    TextField("$", text: $data.deposit)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                }
                LabeledContent("Payment Terms") {
                    TextField("e.g. Due upon pickup", text: $data.paymentTerms)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Pickup / Delivery") {
                    TextField("Location", text: $data.pickupLocation)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                if data.items.isEmpty {
                    Text("No items yet. Tap Add Item.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($data.items) { $line in
                        RentalLineRow(line: $line, catalog: catalog)
                    }
                    .onDelete { data.items.remove(atOffsets: $0) }
                }
                Menu {
                    ForEach(catalog) { item in
                        ForEach(item.tiers) { tier in
                            Button(addItemTitle(item, tier)) {
                                data.items.append(RentalLineItem(itemName: item.name,
                                                                 tierLabel: tier.label,
                                                                 rate: tier.price,
                                                                 quantity: "1"))
                            }
                        }
                    }
                    Button("Other / Custom") {
                        data.items.append(RentalLineItem())
                    }
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            } header: {
                Text("Rental Items")
            } footer: {
                Text("Manage the equipment list and rates in Settings → Rental Items & Rates.")
            }

            Section("Charges") {
                LabeledContent("Subtotal", value: currencyString(data.subtotal))
                if data.damageWaiver == .accepted {
                    LabeledContent("Damage Waiver (10%)", value: currencyString(data.damageWaiverFee))
                }
                HStack {
                    Text("Sales Tax")
                    Spacer()
                    TextField("6.5", value: $taxPercent, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 60)
                    Text("%")
                }
                LabeledContent("Tax", value: currencyString(data.tax(percent: taxPercent)))
                Picker("Payment Method", selection: $data.paymentMethod) {
                    ForEach(PaymentMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                if data.paymentMethod == .card {
                    LabeledContent("Card Fee (3%, non-taxable)", value: currencyString(data.creditCardFee(percent: taxPercent)))
                }
                LabeledContent("Total", value: currencyString(data.totalWithTax(percent: taxPercent)))
                    .font(.headline)
            }

            Section {
                Button {
                    showingCustomerPicker = true
                } label: {
                    Label("Choose from Customers", systemImage: "person.crop.circle")
                }

                Button {
                    showingLicenseScanner = true
                } label: {
                    Label("Scan License & Fill Info", systemImage: "person.text.rectangle")
                }

                if data.isLicenseExpired {
                    Label("License expired — take a new photo.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if data.hasLicense {
                    Label("License on file — valid.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }

                if let imageData = data.licenseImage, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    showingLicensePicker = true
                } label: {
                    Label(data.hasLicense ? "Retake License Photo" : "Take License Photo", systemImage: "camera")
                }

                Toggle("Expiration date on file", isOn: Binding(
                    get: { data.licenseExpiration != nil },
                    set: { on in data.licenseExpiration = on ? (data.licenseExpiration ?? Date()) : nil }
                ))
                if data.licenseExpiration != nil {
                    DatePicker("Expiration", selection: Binding(
                        get: { data.licenseExpiration ?? Date() },
                        set: { data.licenseExpiration = $0 }
                    ), displayedComponents: .date)
                }

                if data.hasLicense {
                    Button("Remove License Photo", role: .destructive) {
                        data.licenseImage = nil
                    }
                }
            } header: {
                Text("Driver License")
            } footer: {
                Text("Scan the barcode on the back of the license to fill in the name, address, and expiration automatically.")
            }

            Section("Damage Waiver (10%)") {
                Picker("Damage Waiver", selection: $data.damageWaiver) {
                    ForEach(DamageWaiverChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                Text("Damage Waiver is not insurance. If accepted, a 10% charge applies and a $2,500 deductible may apply to a claim.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Lessee Signature") {
                SignaturePad(imageData: $data.signatureData)
                if data.signatureData?.isEmpty == false {
                    Button {
                        showingReview = true
                    } label: {
                        Label("Signature Accepted — Review & Send", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                    }
                }
            }

            Section {
                Button {
                    if let url = makePDF() { shareItem = ShareItem(url: url) }
                } label: {
                    Label("Share Agreement (PDF)", systemImage: "square.and.arrow.up")
                }
                Button {
                    if let url = makePDF() { PrintService.present(url) }
                } label: {
                    Label("Print Agreement", systemImage: "printer")
                }
            } footer: {
                Text("Generates the full rental agreement with these details and the signature filled in.")
            }
        }
        .navigationTitle("Rental Agreement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        persistCurrent()
                    } label: {
                        Label("Save", systemImage: "tray.and.arrow.down")
                    }
                    Button {
                        persistCurrent()
                        currentRecord = nil
                        data = RentalAgreementData()
                    } label: {
                        Label("New Agreement", systemImage: "doc.badge.plus")
                    }
                    Button {
                        records = RentalAgreementStorage.loadAll()
                        showingSaves = true
                    } label: {
                        Label("Saved Agreements…", systemImage: "folder")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showingSaves) {
            SavedRentalAgreementsList(records: $records) { rec in
                persistCurrent()
                currentRecord = rec
                data = rec.data
                showingSaves = false
            } onDelete: { rec in
                RentalAgreementStorage.delete(id: rec.id)
                records = RentalAgreementStorage.loadAll()
                if currentRecord?.id == rec.id { currentRecord = nil }
            }
        }
        .fullScreenCover(isPresented: $showingReview) {
            ContractReviewView(title: "Rental Agreement", signature: $data.signatureData) { sig in
                var d = data
                d.signatureData = sig
                let stem = safeFileStem(d.lesseeName, fallback: "Rental-Agreement")
                let url = renderContractPDF(html: RentalAgreementDocument.html(d, taxPercent: taxPercent),
                                            fileName: "Rental-Agreement-\(stem).pdf",
                                            signature: sig,
                                            signatureLabel: "Lessee Signature:")
                // Save a finalized record only once the agreement is actually signed;
                // reuse the same record so re-signing updates it instead of duplicating.
                if sig?.isEmpty == false {
                    var rec = currentRecord ?? RentalAgreementRecord(data: d)
                    rec.data = d
                    rec.signedAt = Date()
                    RentalAgreementStorage.save(rec)
                    currentRecord = rec
                }
                return url
            }
        }
        .sheet(isPresented: $showingLicensePicker) {
            ImageCapturePicker(imageData: $data.licenseImage)
        }
        .sheet(isPresented: $showingLicenseScanner) {
            ImageCapturePicker(imageData: $scanImageData)
        }
        .onChange(of: scanImageData) { _, newValue in
            guard let newValue else { return }
            Task {
                if let scanned = await LicenseScanner.scan(newValue) {
                    var filled: [String] = []
                    if !scanned.fullName.isEmpty {
                        data.lesseeName = scanned.fullName
                        filled.append("name")
                    }
                    if !scanned.address.isEmpty {
                        data.mailingAddress = scanned.address
                        filled.append("address")
                    }
                    if let expiration = scanned.expiration {
                        data.licenseExpiration = expiration
                        filled.append("expiration")
                    }
                    if data.licenseImage == nil { data.licenseImage = newValue }
                    scanMessage = "Filled in \(filled.joined(separator: ", ")) from the license. Double-check before signing."
                } else {
                    scanMessage = "Couldn't read the license. Try the barcode on the back — fill the frame and avoid glare."
                }
                showingScanResult = true
                scanImageData = nil
            }
        }
        .alert("License Scan", isPresented: $showingScanResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanMessage)
        }
        .sheet(isPresented: $showingCustomerPicker) {
            CustomerPickerSheet { picked in
                if !picked.name.isEmpty { data.lesseeName = picked.name }
                if !picked.address.isEmpty { data.mailingAddress = picked.address }
                data.licenseImage = picked.licenseImage
                data.licenseExpiration = picked.licenseExpiration
            }
        }
        .onAppear {
            catalog = RentalCatalogStorage.load()
        }
        .onDisappear {
            persistCurrent()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive { persistCurrent() }
        }
    }

    /// True when nothing meaningful has been entered yet, so nothing is worth saving.
    private var isBlank: Bool {
        data.lesseeName.trimmingCharacters(in: .whitespaces).isEmpty
            && data.items.isEmpty
            && (data.signatureData?.isEmpty ?? true)
    }

    /// Saves the in-progress agreement to the saved-agreements folder,
    /// updating the same record on every save instead of duplicating.
    private func persistCurrent() {
        guard !isBlank else { return }
        var rec = currentRecord ?? RentalAgreementRecord(data: data)
        rec.data = data
        if data.signatureData?.isEmpty == false {
            if rec.signedAt == nil { rec.signedAt = Date() }
        } else {
            rec.signedAt = nil
        }
        RentalAgreementStorage.save(rec)
        currentRecord = rec
        CustomerStorage.upsertAddress(name: data.lesseeName, address: data.mailingAddress)
    }

    private func addItemTitle(_ item: RentalItem, _ tier: RentalTier) -> String {
        let priceSuffix = tier.price.isEmpty ? "" : " ($\(tier.price))"
        return "\(item.name) — \(tier.label)\(priceSuffix)"
    }

    private func makePDF() -> URL? {
        let stem = safeFileStem(data.lesseeName, fallback: "Rental-Agreement")
        return renderContractPDF(html: RentalAgreementDocument.html(data, taxPercent: taxPercent),
                                 fileName: "Rental-Agreement-\(stem).pdf",
                                 signature: data.signatureData,
                                 signatureLabel: "Lessee Signature:")
    }

}

// MARK: - Rental line row

private struct RentalLineRow: View {
    @Binding var line: RentalLineItem
    let catalog: [RentalItem]

    private struct Option: Hashable {
        let key: String
        let display: String
        let itemName: String
        let tierLabel: String
        let price: String
    }

    private let otherKey = "__other__"

    private var options: [Option] {
        catalog.flatMap { item in
            item.tiers.map { tier in
                Option(key: "\(item.name)\u{1}\(tier.label)",
                       display: "\(item.name) — \(tier.label) (\(priceLabel(tier.price)))",
                       itemName: item.name,
                       tierLabel: tier.label,
                       price: tier.price)
            }
        }
    }

    private var currentKey: String {
        let key = "\(line.itemName)\u{1}\(line.tierLabel)"
        return options.contains(where: { $0.key == key }) ? key : otherKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Item", selection: Binding(
                get: { currentKey },
                set: { newKey in
                    if newKey == otherKey {
                        line.tierLabel = ""
                    } else if let option = options.first(where: { $0.key == newKey }) {
                        line.itemName = option.itemName
                        line.tierLabel = option.tierLabel
                        line.rate = option.price
                    }
                }
            )) {
                ForEach(options, id: \.key) { option in
                    Text(option.display).tag(option.key)
                }
                Text("Other / Custom").tag(otherKey)
            }

            if currentKey == otherKey {
                TextField("Item name", text: $line.itemName)
            }

            HStack {
                Text("Qty").foregroundStyle(.secondary)
                TextField("1", text: $line.quantity)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 44)
                Spacer()
                Text("Rate $").foregroundStyle(.secondary)
                TextField("0", text: $line.rate)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
            }

            HStack {
                Spacer()
                Text("Line total: \(currencyString(line.lineTotal))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func priceLabel(_ price: String) -> String {
        let trimmed = price.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "—" : "$\(trimmed)"
    }
}

// MARK: - PDF document (HTML)

enum RentalAgreementDocument {
    static func html(_ d: RentalAgreementData, taxPercent: Double) -> String {
        var s = ""

        s += "<div class=\"header\"><h1>RENTAL AGREEMENT</h1><div class=\"sub\">Terms &amp; Conditions</div></div>"

        s += ContractHTML.field("Lessor:", htmlEscape(ContractHTML.providerName))
        s += ContractHTML.field("Lessee:", fieldValue(d.lesseeName))
        s += ContractHTML.field("Address:", fieldValue(d.mailingAddress))

        if d.items.isEmpty {
            s += ContractHTML.field("Equipment Rented:", "________________________")
        } else {
            var lines = ""
            for item in d.items {
                lines += "\(item.quantityValue)× \(htmlEscape(item.displayName)) @ \(htmlEscape(currencyString(item.rateAmount))) = \(htmlEscape(currencyString(item.lineTotal)))<br>"
            }
            s += "<div class=\"field\"><b>Equipment Rented:</b><br>\(lines)</div>"
        }

        s += ContractHTML.field("Rental Start Date/Time:", htmlEscape(dateTimeString(d.startDate)))
        s += ContractHTML.field("Rental Return Date/Time:", htmlEscape(dateTimeString(d.returnDate)))
        s += ContractHTML.field("Subtotal:", htmlEscape(currencyString(d.subtotal)))
        if d.damageWaiver == .accepted {
            s += ContractHTML.field("Damage Waiver (10%):", htmlEscape(currencyString(d.damageWaiverFee)))
        }
        s += ContractHTML.field("Sales Tax (\(String(format: "%g", taxPercent))%):", htmlEscape(currencyString(d.tax(percent: taxPercent))))
        if d.paymentMethod == .card {
            s += ContractHTML.field("Credit Card Fee (3%, non-taxable):", htmlEscape(currencyString(d.creditCardFee(percent: taxPercent))))
        }
        s += ContractHTML.field("Total:", htmlEscape(currencyString(d.totalWithTax(percent: taxPercent))))
        s += ContractHTML.field("Deposit:", money(d.deposit))
        s += ContractHTML.field("Payment Method:", htmlEscape(d.paymentMethod.rawValue))
        s += ContractHTML.field("Payment:", fieldValue(d.paymentTerms))
        s += ContractHTML.field("Pickup/Delivery Location:", fieldValue(d.pickupLocation))
        s += ContractHTML.field("Driver License:", htmlEscape(licenseSummary(d)))

        s += "<h2>1. INSPECTION</h2><p>Lessee acknowledges that he/she has had an opportunity to personally inspect the equipment, finds it suitable for his/her needs and in good condition, and understands its proper use. Lessee further acknowledges his/her duty to inspect the equipment before use and to notify Lessor immediately of any defects.</p>"

        s += "<h2>2. REPLACEMENT OF MALFUNCTIONING EQUIPMENT</h2><p>If the equipment becomes unsafe or in disrepair as a result of normal use, Lessee agrees to discontinue use immediately and notify Lessor. Lessor may replace the equipment with similar equipment in good working order, if available. Lessor is not responsible for any incidental or consequential damages caused by delays or otherwise.</p>"

        s += "<h2>3. WARRANTIES</h2><p>There are no warranties of merchantability or fitness, either express or implied. There is no warranty that the equipment is suited for Lessee's intended use or that it is free from defects.</p>"

        s += "<h2>4. HOLD HARMLESS AGREEMENT</h2><p>To the fullest extent permitted by law, Lessee agrees to assume the risk of, and hold Lessor harmless from, property damage and personal injuries caused by the equipment and/or arising out of the use, possession, operation, transportation, loading, unloading, or return of the equipment.</p>"

        s += "<h2>5. INDEMNIFICATION</h2>"
        s += "<p>Lessee assumes liability for, and shall indemnify, defend, and hold harmless Lessor, its agents, employees, officers, directors, successors, and assigns from and against any and all liabilities, obligations, losses, demands, damages, injuries, claims, penalties, suits, actions, costs, and expenses, including attorney's fees, of whatsoever kind and nature, relating to or arising out of the use, condition, operation, ownership, selection, delivery, leasing, possession, transportation, or return of the equipment, or any failure on the part of Lessee to perform or comply with the terms and conditions of this agreement.</p>"
        s += "<p>This includes, but is not limited to, claims involving bodily injury, illness, death, property damage, latent defects, other defects, whether or not discoverable by Lessee or Lessor, and claims arising regardless of where, how, or by whom the equipment is operated.</p>"
        s += "<p>Without limiting the generality of the foregoing, Lessee shall, at Lessee's own cost and expense, defend Lessor against all claims, suits, or proceedings commenced by any person or entity in which Lessor is named as a party and in which Lessor is alleged to be liable or responsible as a result of or arising out of the equipment, the lease of the equipment, or any alleged act or omission relating to the equipment.</p>"
        s += "<p>In the event any such action is commenced naming Lessor as a party, Lessor may, in its sole discretion, elect to defend said action on its own behalf with counsel of its choice. Lessee shall be liable for and shall reimburse Lessor for all costs, expenses, and attorney's fees incurred by Lessor in such defense and/or in any settlement, judgment, or other resolution thereof.</p>"
        s += "<p>The indemnities and assumptions of liabilities and obligations herein provided for shall continue in full force and effect notwithstanding the expiration or other termination of this agreement.</p>"
        s += "<p>Purpose of this clause: It is understood and agreed by the parties that the purpose of this clause is to shift, to the fullest extent permitted by law, the risk of claims relating to or arising out of the lease, possession, use, operation, transportation, loading, unloading, or return of the equipment by Lessee. It is the intention of the parties that this clause be interpreted broadly and in favor of Lessor.</p>"

        s += "<h2>6. PROHIBITED USES</h2><p>Use of the equipment in any of the following circumstances is prohibited and constitutes a breach of this agreement:</p>"
        s += "<p>(a) Use for an illegal purpose or in an illegal manner.<br>(b) Use when the equipment is in bad repair or is misused.<br>(c) Improper, unintended, careless, reckless, or negligent use.<br>(d) Use by anyone other than Lessee or Lessee's employees without Lessor's written permission. Lessee may not sublease, rent, lend, transfer, or loan the equipment without Lessor's written permission.<br>(e) Use at a location other than the address furnished to Lessor without Lessor's written permission. This provision does not apply to mobile equipment that is intended to be operated at multiple job locations, provided the equipment remains within the agreed rental area.<br>(f) Use in excess of rated capacity, manufacturer recommendations, safety instructions, or applicable laws, rules, or regulations.<br>(g) Use while under the influence of alcohol, drugs, or any substance that may impair safe operation.</p>"

        s += "<h2>7. TIME OF RETURN</h2><p>Lessee's right to possession terminates upon expiration of the rental period. Retention or possession of the equipment after that time constitutes a material breach of this agreement. Time is of the essence. Any extension of the rental period must be mutually agreed upon in writing.</p>"

        s += "<h2>8. DIRTY, DAMAGED, LOST, OR STOLEN EQUIPMENT</h2>"
        s += "<p>Lessee agrees to pay for any damage to or loss of the equipment, regardless of cause, except for reasonable wear and tear, while the equipment is out of Lessor's possession.</p>"
        s += "<p>Lessee agrees to pay a cleaning charge for equipment returned dirty, with a minimum cleaning charge of $100.00.</p>"
        s += "<p>Equipment that is lost, stolen, or damaged beyond repair shall be paid for by Lessee at the replacement cost of comparable new equipment or, at Lessor's option, the actual cost to replace the equipment.</p>"
        s += "<p>The cost of repairs shall be borne by Lessee, whether performed by Lessor or, at Lessor's option, by others. Accrued rental charges may not be applied against the purchase cost, replacement cost, or repair cost of damaged, lost, or stolen equipment.</p>"
        s += "<p>In the case of loss by theft or other means, Lessee agrees to furnish a police report to Lessor within forty-eight (48) hours.</p>"
        s += "<p>If Lessor must use collection efforts or litigation to recover amounts owed for damage to, loss of, theft of, cleaning of, or repair of the equipment, Lessee agrees to pay all collection fees, attorney's fees, court costs, and other expenses involved in collecting these charges.</p>"

        s += "<h2>9. REPOSSESSION</h2><p>Upon failure to pay rent or upon any other breach of this agreement, Lessor may terminate this agreement and take possession of and remove the equipment from wherever it is located. To the fullest extent permitted by law, Lessor and Lessor's agents shall not be liable for any claims for damage, trespass, loss of time, or inconvenience arising out of the repossession or removal of the equipment.</p>"

        s += "<h2>10. SEVERABILITY</h2><p>The provisions of this agreement are severable. The invalidity, unenforceability, or waiver of any provision shall not affect the validity or enforceability of the remaining provisions of this agreement.</p>"

        s += "<h2>11. WAIVER OF CLAIMS</h2><p>To the fullest extent permitted by law, Lessee waives all claims against Lessor for personal injuries, property damage, damage to transported goods, loss of time, loss of use, business interruption, or inconvenience arising out of the possession, use, operation, transportation, loading, unloading, or return of the rented equipment.</p>"

        s += "<h2>12. LOADING AND UNLOADING EQUIPMENT</h2><p>Lessee is responsible for loading and unloading the equipment. If Lessor or Lessor's employees assist in loading or unloading the equipment, Lessee agrees to assume the risk of, and hold Lessor harmless from, any property damage or personal injuries, including damages or injuries arising out of or attributable to the negligence of Lessor or Lessor's employees, to the fullest extent permitted by law.</p>"

        s += "<h2>13. DAMAGE WAIVER</h2>"
        s += "<p>Damage Waiver is not insurance. If Lessee initials acceptance of the Damage Waiver and pays the applicable Damage Waiver charge, and if Lessee provides immediate notification of any accident or damage and promptly submits any applicable police report or other required documentation, Lessor may waive certain claims against Lessee for direct physical damage to the rented equipment, subject to the terms and exclusions below.</p>"
        s += "<p>Damage Waiver does not apply to, and Lessee remains fully responsible for, the following:</p>"
        s += "<p>(a) Intentional damage.<br>(b) Any item, part, accessory, or equipment not returned for any reason, including theft.<br>(c) Loss or damage resulting from overloading or exceeding the rated capacity of the equipment.<br>(d) Loss or damage to motors, electrical appliances, or electrical devices caused by artificial current, improper voltage, improper connection, or misuse.<br>(e) Loss due to mysterious disappearance, wrongful conversion by a person entrusted with the equipment, or a shortage disclosed on inventory.<br>(f) Loss or damage caused by dishonesty, theft, or conversion by Lessee, Lessee's employees, or persons to whom the equipment is entrusted.<br>(g) Loss or damage resulting from use of the equipment in violation of any provision of this agreement, violation of any law, ordinance, or regulation, or operation in an improper, careless, reckless, or negligent manner.<br>(h) Damage from paint, mud, plaster, concrete, resin, chemicals, or any other material. Lessee is responsible for cleaning and repainting as required.<br>(i) Tires, tracks, belts, hoses, hydraulic lines, glass, blades, teeth, bits, chains, cutting edges, wear parts, or other consumable parts, unless specifically covered in writing by Lessor.<br>(j) Damage caused by failure to check fluids, overheating, lack of lubrication, improper fuel, contaminated fuel, running out of fuel, or failure to operate equipment according to manufacturer instructions.</p>"
        s += "<p>If Lessee has insurance covering such loss or damage, Lessee shall exercise all rights available under said insurance, take all action necessary to process such claim, and assign such claim and any proceeds from such insurance to Lessor to the extent of Lessor's loss. Lessee agrees to provide Lessor with complete information concerning any applicable insurance coverage.</p>"
        s += "<p>A Damage Waiver deductible may apply. If applicable, the deductible amount shall be stated on the front of this agreement or otherwise disclosed in writing.</p>"

        s += "<h2>14. DEFAULT AND COLLECTION COSTS</h2>"
        s += "<p>In the event of default by Lessee, Lessee agrees to pay all costs of collection, including attorney's fees of $500.00 or one-third (1/3) of the delinquent balance, whichever is greater, plus court costs and other collection expenses, to the fullest extent permitted by law.</p>"
        s += "<p>Lessee consents to venue and jurisdiction in the courts of ____________ County, Alabama, for any issue related to this agreement or other matters associated with doing business with Lessor.</p>"

        s += "<h2>15. TAXES AND FEES</h2><p>Lessee is responsible for all applicable taxes, fees, rental taxes, sales taxes, environmental fees, delivery fees, pickup fees, fuel charges, cleaning fees, damage charges, late fees, and other charges associated with this rental, unless otherwise stated in writing.</p>"

        s += "<h2>16. SAFETY INSTRUCTIONS</h2><p>Lessee acknowledges that he/she has received, reviewed, or had the opportunity to review all safety instructions, operating instructions, warnings, and manufacturer recommendations related to the equipment rented. Lessee agrees to use the equipment safely and only for its intended purpose.</p>"

        s += "<h2>17. ENTIRE AGREEMENT</h2><p>This agreement contains the entire agreement between the parties and supersedes all prior oral or written agreements relating to the rental of the equipment. No changes or extensions are valid unless agreed to in writing by Lessor.</p>"

        s += "<div class=\"hr\"></div><h1>DAMAGE WAIVER SELECTION</h1>"
        s += "<p>Damage Waiver Charge: <b>10%</b></p>"
        let accepted = d.damageWaiver == .accepted
        s += "<p>[\(accepted ? "X" : "&nbsp;&nbsp;")] Accepted &nbsp;&nbsp;&nbsp;&nbsp; [\(accepted ? "&nbsp;&nbsp;" : "X")] Declined</p>"
        s += "<p>Damage Waiver Notice: Damage Waiver is not insurance. By initialing acceptance, or by separate written confirmation, Lessee agrees to pay the additional rental charge shown above or, if not shown above, as posted by Lessor. In return, Lessor agrees to waive certain claims for damage to rental item(s), subject to the terms, limitations, exclusions, and deductible stated in this agreement. If applicable, a deductible fee of $2,500.00 will be charged to Lessee in the event a Damage Waiver claim is filed. If Damage Waiver is declined, Lessee is responsible for any and all damage to the equipment incurred during the rental period, except for reasonable wear and tear.</p>"

        s += "<div class=\"hr\"></div><h1>CUSTOMER ACKNOWLEDGMENT</h1>"
        s += "<p>I have read and understand all terms and conditions of this agreement. I have inspected the equipment or had the opportunity to inspect it. I have received safety instructions or had the opportunity to review safety instructions for the proper use and application of the rented equipment. I understand that I am responsible for all damages, loss, theft, cleaning charges, rental charges, taxes, and fees as provided in this agreement.</p>"
        s += "<p><b>CUSTOMER IS RESPONSIBLE FOR ALL DAMAGES EXCEPT AS EXPRESSLY LIMITED BY AN ACCEPTED DAMAGE WAIVER.</b></p>"

        let signedDate = (d.signatureData?.isEmpty == false) ? htmlEscape(longDate(Date())) : "________________"
        s += ContractHTML.field("Lessee Signature:", signatureHTML(d.signatureData))
        s += ContractHTML.field("Printed Name:", fieldValue(d.lesseeName))
        s += ContractHTML.field("Date:", signedDate)
        s += "<p>Thank you for your business.</p>"

        return ContractHTML.page(s)
    }

    private static func licenseSummary(_ d: RentalAgreementData) -> String {
        guard d.hasLicense else { return "Not provided" }
        if let expiration = d.licenseExpiration {
            return "On file, expires \(longDate(expiration))"
        }
        return "On file"
    }
}

// MARK: - Saved Rental Agreements List

private struct SavedRentalAgreementsList: View {
    @Binding var records: [RentalAgreementRecord]
    let onSelect: (RentalAgreementRecord) -> Void
    let onDelete: (RentalAgreementRecord) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { rec in
                    Button {
                        onSelect(rec)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.customerName.isEmpty ? "Unnamed" : rec.customerName)
                                .font(.headline)
                            HStack(spacing: 8) {
                                if let signed = rec.signedAt {
                                    Text("Signed \(signed.formatted(date: .abbreviated, time: .omitted))")
                                } else {
                                    Text("Draft")
                                }
                                Text(rec.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            onDelete(rec)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Saved Agreements")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        records = RentalAgreementStorage.loadAll()
                    } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}
