import SwiftUI

// MARK: - Pricing data (recovered rates)

/// Reference pricing shown in the dropdown; selecting one fills the rate line.
enum AgPricingItem: String, CaseIterable, Identifiable, Codable {
    case custom
    case forestryMulchingLabor
    case skidSteerLabor
    case miniExcavatorLabor
    case sawmillingPineUpTo16
    case sawmillingPine16To20
    case sawmillingHardwoodUpTo16
    case sawmillingHardwood16To20
    case portableSawmillingMinimum

    var id: String { rawValue }

    var serviceName: String {
        switch self {
        case .custom: return "Manual / Custom"
        case .forestryMulchingLabor: return "Forestry Mulching (Labor)"
        case .skidSteerLabor: return "Skid Steer (Labor)"
        case .miniExcavatorLabor: return "Mini Excavator (Labor)"
        case .sawmillingPineUpTo16: return "Sawmilling (Pine) up to 16 ft"
        case .sawmillingPine16To20: return "Sawmilling (Pine) 16 to 20 ft"
        case .sawmillingHardwoodUpTo16: return "Sawmilling (Hardwood) up to 16 ft"
        case .sawmillingHardwood16To20: return "Sawmilling (Hardwood) 16 to 20 ft"
        case .portableSawmillingMinimum: return "Portable Sawmilling Minimum"
        }
    }

    var rateDescription: String {
        switch self {
        case .custom: return ""
        case .forestryMulchingLabor: return "$190 per hour, half day minimum plus $300 transport fee"
        case .skidSteerLabor: return "$160 per hour, half day minimum plus $300 transport fee"
        case .miniExcavatorLabor: return "$150 per hour, half day minimum plus $300 transport fee"
        case .sawmillingPineUpTo16: return "$0.60 per board foot"
        case .sawmillingPine16To20: return "$0.70 per board foot"
        case .sawmillingHardwoodUpTo16: return "$0.70 per board foot"
        case .sawmillingHardwood16To20: return "$0.80 per board foot"
        case .portableSawmillingMinimum: return "$1,500 plus $300 transport = $1,800 total"
        }
    }
}

/// Selectable services with hourly rates used to compute the job total.
enum AgServiceType: String, CaseIterable, Identifiable, Codable {
    case bushHogging = "Bush Hogging"
    case disking = "Disking"
    case foodPlotPrep = "Food Plot Prep"
    case seeding = "Seeding"
    case debrisRemoval = "Debris Removal"
    case drivewayRepair = "Driveway Repair"
    case grading = "Grading"
    case selectiveForestryMulching = "Selective Forestry Mulching"
    case customWork = "Custom Work"

    var id: String { rawValue }

    var hourlyRate: Double? {
        switch self {
        case .bushHogging, .disking, .foodPlotPrep, .seeding: return 100
        case .debrisRemoval, .drivewayRepair, .grading: return 160
        case .selectiveForestryMulching: return 190
        case .customWork: return nil
        }
    }

    var displayName: String {
        if let rate = hourlyRate { return "\(rawValue) — $\(Int(rate))/hr" }
        return rawValue
    }
}

// MARK: - Model

struct AgServicesData: Codable, Equatable, Hashable {
    var customerName = ""
    var propertyAddress = ""
    var mailingAddress = ""
    var phone = ""
    var email = ""
    var agreementDate = Date()
    var startDate = Date()
    var completionDate = Date()

    var selectedPricingItem: AgPricingItem = .custom
    var rateText = ""
    var transportationFee = "300"
    var deposit = ""
    var lateFeeInterest = ""

    var selectedServices: Set<AgServiceType> = []
    var serviceHours: [String: String] = [:]   // keyed by AgServiceType.rawValue
    var workDescription = ""
    var marketingDeclined = false
    var signatureData: Data?
    // Stored as an optional raw value so agreements saved before this field existed still decode.
    var paymentMethodRaw: String?

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw ?? "") ?? .cash }
        set { paymentMethodRaw = newValue.rawValue }
    }

    var laborTotal: Double {
        selectedServices.reduce(0) { sum, type in
            guard let rate = type.hourlyRate else { return sum }
            return sum + rate * parseAmount(serviceHours[type.rawValue] ?? "")
        }
    }

    /// 3% surcharge on the amount charged when paying by card; not taxed.
    var creditCardFee: Double {
        paymentMethod == .card ? (laborTotal + parseAmount(transportationFee)) * 0.03 : 0
    }

    var estimatedTotal: Double {
        laborTotal + parseAmount(transportationFee) + creditCardFee
    }

    /// Selected services in a stable display order.
    var orderedSelectedServices: [AgServiceType] {
        AgServiceType.allCases.filter { selectedServices.contains($0) }
    }
}

// MARK: - View

struct AgriculturalServicesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var data = AgServicesData()
    @State private var shareItem: ShareItem?
    @State private var showingReview = false
    @State private var showingRates = false
    @State private var showingSaves = false
    @State private var records: [AgServicesRecord] = []
    @State private var currentRecord: AgServicesRecord?
    @State private var showingLicenseScanner = false
    @State private var scanImageData: Data?
    @State private var showingScanResult = false
    @State private var scanMessage = ""

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

            Section("Customer") {
                CustomerSuggestionField(title: "Customer / Owner", name: $data.customerName) { picked in
                    if !picked.phone.isEmpty { data.phone = picked.phone }
                    if !picked.email.isEmpty { data.email = picked.email }
                    if !picked.address.isEmpty { data.mailingAddress = picked.address }
                }
                textRow("Property / Job Location", text: $data.propertyAddress)
                textRow("Mailing Address", text: $data.mailingAddress)
                textRow("Phone", text: $data.phone, keyboard: .phonePad)
                textRow("Email", text: $data.email, keyboard: .emailAddress)
                Button {
                    showingLicenseScanner = true
                } label: {
                    Label("Scan License & Fill Info", systemImage: "person.text.rectangle")
                }
            }

            Section("Dates") {
                DatePicker("Date of Agreement", selection: $data.agreementDate, displayedComponents: .date)
                DatePicker("Estimated Start", selection: $data.startDate, displayedComponents: .date)
                DatePicker("Estimated Completion", selection: $data.completionDate, displayedComponents: .date)
            }

            Section("Pricing") {
                Picker("Rate", selection: $data.selectedPricingItem) {
                    ForEach(AgPricingItem.allCases) { item in
                        Text(item.serviceName).tag(item)
                    }
                }
                .onChange(of: data.selectedPricingItem) { _, item in
                    if item != .custom { data.rateText = item.rateDescription }
                }
                if data.selectedPricingItem != .custom {
                    Text(data.selectedPricingItem.rateDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Rate / Price") {
                    TextField("Rate", text: $data.rateText)
                        .multilineTextAlignment(.trailing)
                }
                Button {
                    showingRates = true
                } label: {
                    Label("View Rate Sheet", systemImage: "list.bullet.clipboard")
                }
                moneyRow("Transportation / Mobilization", text: $data.transportationFee)
                moneyRow("Deposit Required", text: $data.deposit)
                textRow("Late Fee / Interest", text: $data.lateFeeInterest)
                Picker("Payment Method", selection: $data.paymentMethod) {
                    ForEach(PaymentMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
            }

            Section("Services to Perform") {
                ForEach(AgServiceType.allCases) { service in
                    Button {
                        toggle(service)
                    } label: {
                        HStack {
                            Image(systemName: data.selectedServices.contains(service) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(data.selectedServices.contains(service) ? Color.accentColor : .secondary)
                            Text(service.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
            }

            if !data.orderedSelectedServices.isEmpty {
                Section("Hours & Total") {
                    ForEach(data.orderedSelectedServices) { service in
                        if let rate = service.hourlyRate {
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent(service.rawValue) {
                                    HStack(spacing: 4) {
                                        SelectAllTextField(placeholder: "0", text: hoursBinding(for: service), keyboard: .decimalPad)
                                            .frame(maxWidth: 70)
                                        Text("hrs").foregroundStyle(.secondary)
                                    }
                                }
                                Text("\(hoursText(service)) × \(currencyString(rate))/hr = \(currencyString(rate * parseAmount(data.serviceHours[service.rawValue] ?? "")))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("\(service.rawValue): custom rate (entered above)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Labor Subtotal", value: currencyString(data.laborTotal))
                    LabeledContent("Transportation", value: currencyString(parseAmount(data.transportationFee)))
                    if data.paymentMethod == .card {
                        LabeledContent("Card Fee (3%, non-taxable)", value: currencyString(data.creditCardFee))
                    }
                    LabeledContent("Estimated Total", value: currencyString(data.estimatedTotal))
                        .font(.headline)
                }
            }

            Section("Description of Work") {
                TextField("Describe the work to be performed", text: $data.workDescription, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section("Photos & Marketing") {
                Toggle("Customer declines marketing photos/videos", isOn: $data.marketingDeclined)
            }

            Section("Customer Signature") {
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
                Text("Generates the full agricultural services agreement with these details and the signature filled in.")
            }
        }
        .navigationTitle("Agricultural Services")
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
                        data = AgServicesData()
                    } label: {
                        Label("New Agreement", systemImage: "doc.badge.plus")
                    }
                    Button {
                        records = AgServicesStorage.loadAll()
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
            SavedAgServicesList(records: $records) { rec in
                persistCurrent()
                currentRecord = rec
                data = rec.data
                showingSaves = false
            } onDelete: { rec in
                AgServicesStorage.delete(id: rec.id)
                records = AgServicesStorage.loadAll()
                if currentRecord?.id == rec.id { currentRecord = nil }
            }
        }
        .fullScreenCover(isPresented: $showingReview) {
            ContractReviewView(title: "Agricultural Services", signature: $data.signatureData) { sig in
                var d = data
                d.signatureData = sig
                let stem = safeFileStem(data.customerName, fallback: "Ag-Services-Agreement")
                let url = renderContractPDF(html: AgServicesDocument.html(d),
                                            fileName: "Ag-Services-\(stem).pdf",
                                            signature: sig,
                                            signatureLabel: "Customer / Property Owner Signature:")
                // Save a finalized record (for the financial report) only once signed;
                // reuse the same record so re-signing updates it instead of duplicating.
                if sig?.isEmpty == false {
                    var rec = currentRecord ?? AgServicesRecord(data: d)
                    rec.data = d
                    rec.signedAt = Date()
                    AgServicesStorage.save(rec)
                    currentRecord = rec
                }
                return url
            }
        }
        .sheet(isPresented: $showingRates) {
            AgRateSheet()
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
                        data.customerName = scanned.fullName
                        filled.append("name")
                    }
                    if !scanned.address.isEmpty {
                        data.mailingAddress = scanned.address
                        filled.append("address")
                    }
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
        .onDisappear {
            persistCurrent()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive { persistCurrent() }
        }
    }

    /// True when nothing meaningful has been entered yet, so nothing is worth saving.
    private var isBlank: Bool {
        data.customerName.trimmingCharacters(in: .whitespaces).isEmpty
            && data.selectedServices.isEmpty
            && data.workDescription.trimmingCharacters(in: .whitespaces).isEmpty
            && (data.signatureData?.isEmpty ?? true)
    }

    /// Saves the in-progress agreement to the saved-agreements folder,
    /// updating the same record on every save instead of duplicating.
    private func persistCurrent() {
        guard !isBlank else { return }
        var rec = currentRecord ?? AgServicesRecord(data: data)
        rec.data = data
        if data.signatureData?.isEmpty == false {
            if rec.signedAt == nil { rec.signedAt = Date() }
        } else {
            rec.signedAt = nil
        }
        AgServicesStorage.save(rec)
        currentRecord = rec
        CustomerStorage.upsertAddress(name: data.customerName, address: data.mailingAddress)
    }

    private func toggle(_ service: AgServiceType) {
        if data.selectedServices.contains(service) {
            data.selectedServices.remove(service)
        } else {
            data.selectedServices.insert(service)
        }
    }

    private func hoursBinding(for service: AgServiceType) -> Binding<String> {
        Binding(
            get: { data.serviceHours[service.rawValue] ?? "" },
            set: { data.serviceHours[service.rawValue] = $0 }
        )
    }

    private func hoursText(_ service: AgServiceType) -> String {
        let hours = parseAmount(data.serviceHours[service.rawValue] ?? "")
        return hours.formatted(.number.precision(.fractionLength(0...2))) + " hrs"
    }

    @ViewBuilder
    private func textRow(_ label: String, text: Binding<String>,
                         keyboard: UIKeyboardType = .default,
                         autocap: TextInputAutocapitalization = .sentences) -> some View {
        LabeledContent(label) {
            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
        }
    }

    @ViewBuilder
    private func moneyRow(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("$", text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
        }
    }

    private func makePDF() -> URL? {
        let stem = safeFileStem(data.customerName, fallback: "Ag-Services-Agreement")
        return renderContractPDF(html: AgServicesDocument.html(data),
                                 fileName: "Ag-Services-\(stem).pdf",
                                 signature: data.signatureData,
                                 signatureLabel: "Customer / Property Owner Signature:")
    }
}

// MARK: - Saved Ag Service Agreements List

private struct SavedAgServicesList: View {
    @Binding var records: [AgServicesRecord]
    let onSelect: (AgServicesRecord) -> Void
    let onDelete: (AgServicesRecord) -> Void
    @Environment(\.dismiss) private var dismiss

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
                        records = AgServicesStorage.loadAll()
                    } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Rate sheet

private struct AgRateSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Labor & Sawmilling") {
                    ForEach(AgPricingItem.allCases.filter { $0 != .custom }, id: \.self) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.serviceName).font(.subheadline.weight(.semibold))
                            Text(item.rateDescription).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Agricultural Services (hourly)") {
                    ForEach(AgServiceType.allCases.filter { $0.hourlyRate != nil }, id: \.self) { type in
                        LabeledContent(type.rawValue, value: "$\(Int(type.hourlyRate ?? 0))/hr")
                    }
                    LabeledContent("Transportation fee", value: "$300")
                }
            }
            .navigationTitle("Rate Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - PDF document (HTML)

enum AgServicesDocument {
    static func html(_ d: AgServicesData) -> String {
        var s = ""

        s += "<div class=\"header\"><h1>AGRICULTURAL SERVICES AGREEMENT</h1><div class=\"sub\">Liability-Limited Service Contract</div></div>"

        s += ContractHTML.field("Service Provider:", htmlEscape(ContractHTML.providerName))
        s += ContractHTML.field("Customer / Property Owner:", fieldValue(d.customerName))
        s += ContractHTML.field("Property Address / Job Location:", fieldValue(d.propertyAddress))
        s += ContractHTML.field("Mailing Address:", fieldValue(d.mailingAddress))
        s += ContractHTML.field("Phone:", fieldValue(d.phone))
        s += ContractHTML.field("Email:", fieldValue(d.email))
        s += ContractHTML.field("Date of Agreement:", htmlEscape(longDate(d.agreementDate)))
        s += ContractHTML.field("Estimated Start Date:", htmlEscape(longDate(d.startDate)))
        s += ContractHTML.field("Estimated Completion Date:", htmlEscape(longDate(d.completionDate)))
        s += "<div class=\"hr\"></div>"

        s += "<h2>1. SERVICES TO BE PERFORMED</h2><p>Customer hires Service Provider to perform the following agricultural, land management, equipment, or related services:</p>"
        if d.orderedSelectedServices.isEmpty {
            s += "<p>____________________________________________</p>"
        } else {
            var lines = ""
            for service in d.orderedSelectedServices {
                if let rate = service.hourlyRate {
                    let hours = parseAmount(d.serviceHours[service.rawValue] ?? "")
                    let sub = rate * hours
                    lines += "• \(htmlEscape(service.rawValue)) — \(hours.formatted(.number.precision(.fractionLength(0...2)))) hrs × \(currencyString(rate))/hr = \(currencyString(sub))<br>"
                } else {
                    lines += "• \(htmlEscape(service.rawValue))<br>"
                }
            }
            s += "<p>\(lines)</p>"
        }
        s += "<p><b>Description of work:</b> \(multilineValue(d.workDescription))</p>"
        s += "<p>Service Provider will perform only the work specifically described in this agreement or in a written change order signed or approved by both parties.</p>"

        s += "<h2>2. PRICE, RATE, AND PAYMENT TERMS</h2>"
        let pricingName = d.selectedPricingItem == .custom ? "" : "\(htmlEscape(d.selectedPricingItem.serviceName)) — "
        s += "<p><b>Rate / Price:</b> \(pricingName)\(fieldValue(d.rateText))</p>"
        s += ContractHTML.field("Transportation / mobilization fee:", money(d.transportationFee))
        s += ContractHTML.field("Deposit required:", money(d.deposit))
        s += ContractHTML.field("Payment method:", htmlEscape(d.paymentMethod.rawValue))
        if !d.orderedSelectedServices.isEmpty {
            s += ContractHTML.field("Labor subtotal:", htmlEscape(currencyString(d.laborTotal)))
        }
        if d.paymentMethod == .card {
            s += ContractHTML.field("Credit card fee (3%, non-taxable):", htmlEscape(currencyString(d.creditCardFee)))
        }
        s += ContractHTML.field("Estimated total:", htmlEscape(currencyString(d.estimatedTotal)))
        s += "<p>Customer agrees to pay all amounts due upon completion of the work unless otherwise agreed in writing. Service Provider may require payment before unloading equipment, beginning work, or continuing work.</p>"
        s += "<p>If payment is not made when due, Customer agrees to pay all costs of collection, including reasonable attorney's fees, court costs, filing fees, and collection expenses, to the fullest extent permitted by law.</p>"

        s += "<h2>3. CUSTOMER REPRESENTATIONS</h2><p>Customer represents and warrants that:</p>"
        s += "<p>1. Customer owns the property or has full legal authority from the property owner to authorize the work.<br>2. Customer has identified and clearly marked all property lines, corners, easements, restricted areas, septic systems, wells, water lines, gas lines, power lines, irrigation lines, fiber optic lines, underground utilities, drain fields, culverts, fences, gates, landscaping, structures, gravesites, survey markers, and any other items that may be damaged or affected by the work.<br>3. Customer has obtained all required permissions, permits, approvals, and authorizations necessary for the work.<br>4. Customer has disclosed all known hazards, wet areas, sinkholes, soft ground, buried debris, stumps, old foundations, underground tanks, wires, pipes, hazardous materials, and other site conditions that could affect the work.<br>5. Customer has confirmed that the work area is accessible for trucks, trailers, and heavy equipment.</p>"
        s += "<p>Service Provider is entitled to rely on Customer's representations. Customer accepts responsibility for damages, delays, costs, claims, or disputes resulting from inaccurate, incomplete, or missing information provided by Customer.</p>"

        s += "<h2>4. PROPERTY LINES, BOUNDARIES, AND MARKING RESPONSIBILITY</h2>"
        s += "<p>Customer is solely responsible for identifying and marking all property boundaries and work limits before Service Provider begins work.</p>"
        s += "<p>Service Provider is not responsible for surveying, verifying property lines, locating corners, determining ownership boundaries, or determining whether vegetation, trees, fences, or other property belongs to Customer or another person.</p>"
        s += "<p>If Customer directs Service Provider to work near a property line, fence, easement, right-of-way, neighboring property, road, ditch, creek, or utility area, Customer assumes all risk and responsibility for such direction.</p>"
        s += "<p>Customer agrees to indemnify, defend, and hold harmless Service Provider from any claim made by a neighbor, adjoining landowner, utility company, governmental entity, or other third party arising out of disputed boundaries, mistaken property lines, unauthorized work areas, or Customer's instructions.</p>"

        s += "<h2>5. UNDERGROUND UTILITIES AND HIDDEN CONDITIONS</h2>"
        s += "<p>Customer is responsible for locating, identifying, and marking all underground utilities and hidden conditions before work begins, including but not limited to water lines, power lines, gas lines, fiber optic lines, septic tanks, drain fields, field lines, sprinkler systems, culverts, irrigation lines, wells, and buried structures.</p>"
        s += "<p>Service Provider is not liable for damage to underground, hidden, buried, covered, concealed, or unmarked items unless caused by Service Provider's gross negligence or intentional misconduct.</p>"
        s += "<p>Customer agrees to pay for any downtime, repair costs, replacement costs, cleanup costs, towing, recovery, or other expenses caused by unmarked or incorrectly marked underground utilities or hidden conditions.</p>"

        s += "<h2>6. ACCESS, GATES, ROADS, DRIVEWAYS, AND GROUND CONDITIONS</h2>"
        s += "<p>Customer is responsible for providing safe and suitable access to the work site for trucks, trailers, equipment, and personnel.</p>"
        s += "<p>Customer understands that heavy equipment may leave tracks, ruts, impressions, soil disturbance, grass damage, driveway damage, road damage, gravel displacement, or other surface disturbance, especially in wet, soft, muddy, sandy, steep, or unstable ground conditions.</p>"
        s += "<p>Unless specifically agreed in writing, Service Provider is not responsible for repairing ruts, tracks, grass damage, driveway damage, gravel displacement, soil compaction, or normal site disturbance caused by reasonable use of equipment while performing the work.</p>"
        s += "<p>If equipment becomes stuck due to ground conditions, hidden hazards, soft areas, wet areas, or Customer-directed access routes, Customer agrees to pay for recovery, towing, repair, cleanup, and related downtime unless caused solely by Service Provider's gross negligence or intentional misconduct.</p>"

        s += "<h2>7. TREES, VEGETATION, DEBRIS, AND FINAL APPEARANCE</h2>"
        s += "<p>Customer understands that land clearing, mulching, excavation, grading, and agricultural services may result in disturbed soil, exposed roots, remaining stumps, uneven ground, wood chips, mulch piles, debris, tire tracks, and changes to drainage or surface conditions.</p>"
        s += "<p>Unless specifically stated in writing, Service Provider does not guarantee:<br>1. Complete removal of all roots, stumps, rocks, vines, or buried debris.<br>2. Grass growth, seed germination, or erosion prevention.<br>3. A finish-grade surface suitable for construction, paving, landscaping, or planting.<br>4. Drainage performance after storms or future weather events.<br>5. Survival of nearby trees, shrubs, grass, landscaping, or vegetation.<br>6. Elimination of regrowth, weeds, invasive species, or future vegetation.</p>"
        s += "<p>Customer is responsible for inspecting the work before Service Provider leaves the job site. If Customer requests additional work, rework, cleanup, grading, hauling, or finishing beyond the original scope, such work will be billed separately.</p>"

        s += "<h2>8. WEATHER, DELAYS, AND SITE CONDITIONS</h2>"
        s += "<p>Work may be delayed, interrupted, rescheduled, or stopped due to weather, wet ground, unsafe conditions, equipment breakdown, material availability, access problems, hidden site conditions, or other circumstances beyond Service Provider's reasonable control.</p>"
        s += "<p>Service Provider is not responsible for delays caused by weather, ground conditions, Customer delays, utility marking delays, permit delays, equipment repair, or events outside Service Provider's control.</p>"
        s += "<p>If the job site becomes unsafe or unsuitable, Service Provider may stop work and resume when conditions improve. Customer remains responsible for work already performed, mobilization charges, transportation fees, and any additional costs caused by delay or changed conditions.</p>"

        s += "<h2>9. CHANGE ORDERS AND ADDITIONAL WORK</h2>"
        s += "<p>Any work not specifically listed in this agreement is excluded unless approved by both parties.</p>"
        s += "<p>Additional work may include, but is not limited to, extra acres, additional clearing, stump removal, rock removal, debris hauling, regrading, culvert repair, drainage correction, road repair, fence repair, cleanup, return trips, or work outside the marked area.</p>"
        s += "<p>Additional work will be billed at Service Provider's current rate unless otherwise agreed in writing. Customer may approve changes by written signature, text message, email, or other written confirmation.</p>"

        s += "<h2>10. LIMITATION OF LIABILITY</h2>"
        s += "<p>To the fullest extent permitted by law, Service Provider's total liability for any claim arising out of or relating to this agreement, the work, the equipment, or the job site shall not exceed the amount actually paid by Customer to Service Provider for the specific work giving rise to the claim.</p>"
        s += "<p>Service Provider shall not be liable for incidental, indirect, special, consequential, punitive, or lost-profit damages, including but not limited to loss of use, loss of business, loss of crop value, loss of timber value, loss of production, loss of access, delay damages, inconvenience, diminution in property value, or emotional distress.</p>"
        s += "<p>This limitation does not apply to damages caused by Service Provider's intentional misconduct or gross negligence where such limitation is not permitted by law.</p>"

        s += "<h2>11. CUSTOMER ASSUMPTION OF RISK</h2>"
        s += "<p>Customer understands that agricultural, forestry, excavation, mulching, and heavy equipment work involves risk of property disturbance and damage, including but not limited to ruts, soil displacement, grass damage, driveway damage, broken limbs, flying debris, dust, rocks, vibration, noise, drainage changes, and contact with hidden or unmarked objects.</p>"
        s += "<p>Customer assumes the ordinary and foreseeable risks associated with the work and agrees that such conditions do not constitute defective work unless Service Provider fails to perform the work in a commercially reasonable manner.</p>"

        s += "<h2>12. INDEMNIFICATION</h2>"
        s += "<p>To the fullest extent permitted by law, Customer agrees to indemnify, defend, and hold harmless Service Provider, its owner, agents, employees, subcontractors, successors, and assigns from and against any and all claims, demands, damages, losses, liabilities, penalties, fines, costs, expenses, attorney's fees, suits, or causes of action arising out of or relating to:</p>"
        s += "<p>1. Customer's instructions or requested work.<br>2. Incorrect, incomplete, or missing property line information.<br>3. Work performed in an area Customer identified or approved.<br>4. Damage to unmarked, mismarked, hidden, buried, or concealed utilities or property.<br>5. Claims by neighbors, landowners, tenants, guests, invitees, utility companies, governmental entities, or other third parties.<br>6. Customer's failure to obtain permits, approvals, or permission.<br>7. Customer's failure to disclose hazards or site conditions.<br>8. Customer's breach of this agreement.<br>9. Use of the property after the work is performed.<br>10. Conditions existing on the property before Service Provider began work.</p>"
        s += "<p>This indemnification obligation shall survive completion of the work, payment, cancellation, or termination of this agreement.</p>"

        s += "<h2>13. INSURANCE</h2>"
        s += "<p>Customer is responsible for maintaining appropriate property insurance, farm insurance, liability insurance, homeowner's insurance, commercial insurance, or other coverage applicable to the property and the work.</p>"
        s += "<p>Upon request, Customer agrees to provide evidence of insurance coverage before work begins. Service Provider is not responsible for any loss that is covered or should have been covered by Customer's insurance.</p>"

        s += "<h2>14. CUSTOMER RESPONSIBILITY FOR PERMITS AND COMPLIANCE</h2>"
        s += "<p>Unless otherwise agreed in writing, Customer is responsible for obtaining all permits, approvals, licenses, right-of-way permissions, environmental permissions, burn permissions, erosion control approvals, land disturbance approvals, utility clearances, and other legal authorizations necessary for the work.</p>"
        s += "<p>Customer agrees to be responsible for any fines, penalties, stop-work orders, remediation costs, or claims resulting from Customer's failure to obtain required permits or approvals.</p>"

        s += "<h2>15. WORK NEAR STRUCTURES, FENCES, UTILITIES, AND PERSONAL PROPERTY</h2>"
        s += "<p>Customer is responsible for removing vehicles, trailers, equipment, livestock, pets, tools, decorations, personal property, fencing materials, irrigation components, and other movable items from the work area before Service Provider begins work.</p>"
        s += "<p>Work near buildings, fences, gates, mailboxes, signs, wells, tanks, utilities, landscaping, or other improvements carries increased risk. Customer accepts this risk when directing or approving work in those areas.</p>"
        s += "<p>Unless specifically agreed in writing, Service Provider is not responsible for damage to items left in or near the work area, unmarked items, fragile items, pre-existing defective items, or items located where equipment must reasonably operate.</p>"

        s += "<h2>16. RIGHT TO STOP WORK</h2>"
        s += "<p>Service Provider may stop work at any time if:<br>1. Conditions are unsafe.<br>2. Customer fails to pay as agreed.<br>3. Customer changes the scope without written agreement.<br>4. Hidden conditions are discovered.<br>5. Property lines or utilities are unclear.<br>6. Customer or another person interferes with the work.<br>7. Equipment access is unsafe or unsuitable.<br>8. Continuing work could create unreasonable risk.</p>"
        s += "<p>If work is stopped for any of these reasons, Customer remains responsible for work performed, transportation fees, mobilization charges, downtime, and any other charges incurred through the date work stops.</p>"

        s += "<h2>17. PHOTOS AND DOCUMENTATION</h2>"
        s += "<p>Customer authorizes Service Provider to take photos and videos of the property, work area, equipment, before-and-after conditions, and completed work for documentation, dispute prevention, marketing, and business records.</p>"
        s += "<p>Service Provider will not intentionally disclose Customer's private personal information in marketing materials.</p>"
        s += "<p>Marketing photos/videos declined: \(d.marketingDeclined ? "[X] Yes" : "[&nbsp;&nbsp;] No")</p>"

        s += "<h2>18. PAYMENT DEFAULT</h2>"
        s += "<p>If Customer fails to pay when due, Service Provider may charge interest, late fees, collection costs, attorney's fees, court costs, and any other costs allowed by law.</p>"
        let lateFee = d.lateFeeInterest.trimmingCharacters(in: .whitespacesAndNewlines)
        s += "<p><b>Late fee / interest:</b> \(lateFee.isEmpty ? "____________" : htmlEscape(lateFee))</p>"
        s += "<p>Customer agrees that venue and jurisdiction for any dispute related to this agreement shall be in the courts of ____________ County, Alabama, unless otherwise required by law.</p>"

        s += "<h2>19. NO GUARANTEE OF SPECIFIC RESULT</h2>"
        s += "<p>Service Provider will make commercially reasonable efforts to perform the work described in this agreement. However, Service Provider does not guarantee any particular outcome, crop yield, drainage result, final grade, soil condition, grass growth, resale value, timber value, property value, visual appearance, or future condition unless specifically stated in writing.</p>"

        s += "<h2>20. SEVERABILITY</h2>"
        s += "<p>If any provision of this agreement is found invalid or unenforceable, the remaining provisions shall remain in full force and effect.</p>"

        s += "<h2>21. ENTIRE AGREEMENT</h2>"
        s += "<p>This agreement contains the entire agreement between the parties. No oral statements, prior discussions, estimates, advertisements, text messages, or assumptions shall modify this agreement unless confirmed in writing by both parties.</p>"

        s += "<div class=\"hr\"></div><h1>CUSTOMER ACKNOWLEDGMENT</h1>"
        s += "<p>Customer acknowledges that he/she has read and understands this agreement, has had an opportunity to ask questions, and agrees to be bound by its terms. Customer understands that heavy equipment and agricultural services involve risk of property disturbance and damage, and Customer accepts those risks as stated in this agreement.</p>"

        let signedDate = (d.signatureData?.isEmpty == false) ? htmlEscape(longDate(Date())) : "________________"
        s += ContractHTML.field("Customer / Property Owner Signature:", signatureHTML(d.signatureData))
        s += ContractHTML.field("Printed Name:", fieldValue(d.customerName))
        s += ContractHTML.field("Date:", signedDate)

        s += "<div class=\"hr\"></div><h1>SERVICE PROVIDER ACCEPTANCE</h1>"
        s += "<p>\(htmlEscape(ContractHTML.providerName))</p>"
        s += ContractHTML.field("Authorized Representative:", "________________________")
        s += ContractHTML.field("Date:", "________________")

        return ContractHTML.page(s)
    }
}
