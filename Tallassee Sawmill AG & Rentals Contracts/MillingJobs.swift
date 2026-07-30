import SwiftUI
import Foundation

// MARK: - Models

struct MillingLine: Identifiable, Codable, Hashable {
    var id = UUID()
    var species: WoodSpecies = .pine
    var sizeType: SizeType = .trueSize
    var thicknessIn: String = "1"
    var widthIn: String = "6"
    var lengthFt: String = "8"
    var quantity: String = "1"

    var bfPerPiece: Double {
        let t = SawmillPricing.number(thicknessIn)
        let w = SawmillPricing.number(widthIn)
        let l = SawmillPricing.number(lengthFt)
        return max(0, (t * w * l) / 12.0)
    }
    var totalBF: Double { bfPerPiece * Double(Int(quantity.filter { $0.isNumber }) ?? 0) }

    /// Sawmilling rate for customer-supplied logs; editable in Settings → Milling Rates.
    var ratePerBF: Double {
        MillingRates.current.rate(species: species, lengthFt: SawmillPricing.number(lengthFt))
    }
    var lineTotal: Double { totalBF * ratePerBF }
}

// MARK: - Editable milling rates

/// User-adjustable rates for milling customer-supplied logs, $/BF by species group and log length.
struct MillingRates: Codable, Equatable {
    var pineUpTo16: Double
    var pine16To20: Double
    var hardwoodUpTo16: Double
    var hardwood16To20: Double

    static let storageKey = "millingRates"

    /// Defaults from the ag services rate sheet.
    static var defaults: MillingRates {
        MillingRates(pineUpTo16: 0.60, pine16To20: 0.70, hardwoodUpTo16: 0.70, hardwood16To20: 0.80)
    }

    /// The saved rates, or defaults if none saved.
    static var current: MillingRates {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(MillingRates.self, from: data) else {
            return defaults
        }
        return decoded
    }

    static func save(_ rates: MillingRates) {
        if let data = try? JSONEncoder().encode(rates) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Pine uses the pine rates; every other species uses the hardwood rates.
    func rate(species: WoodSpecies, lengthFt: Double) -> Double {
        let isLong = lengthFt > 16
        if species.isPine {
            return isLong ? pine16To20 : pineUpTo16
        }
        return isLong ? hardwood16To20 : hardwoodUpTo16
    }
}

// MARK: - Rates editor (Settings)

struct MillingRatesEditor: View {
    @State private var rates = MillingRates.current

    var body: some View {
        Form {
            Section("Pine — $/BF") {
                rateRow("Up to 16 ft", value: $rates.pineUpTo16)
                rateRow("16–20 ft", value: $rates.pine16To20)
            }

            Section("Hardwood & Other Species — $/BF") {
                rateRow("Up to 16 ft", value: $rates.hardwoodUpTo16)
                rateRow("16–20 ft", value: $rates.hardwood16To20)
            }

            Section {
                Button(role: .destructive) {
                    rates = MillingRates.defaults
                } label: {
                    Label("Reset to Default Rates", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text("Rates for milling customer-supplied logs. All non-pine species use the hardwood rate.")
            }
        }
        .navigationTitle("Milling Rates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onChange(of: rates) { _, newValue in
            MillingRates.save(newValue)
        }
    }

    private func rateRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("$")
            TextField("0.00", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 70)
            Text("/BF").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MillingJob: Identifiable, Codable, Hashable {
    /// Flat charge for hauling the sawmill or skid steer to the job site.
    static let mobilizationFee = 300.0

    var id = UUID()
    /// Sequential number behind the human-readable job ID ("MILL-0007").
    /// 0 = not yet assigned (jobs saved before this field existed).
    var jobNumber: Int = 0
    var customerName: String = ""
    var date: Date = Date()
    var notes: String = ""
    var completed: Bool = false
    var sawmillMobilization: Bool = false
    var skidSteerMobilization: Bool = false
    var lines: [MillingLine] = []
    
    // Job media (photos/videos with Before/After labels)
    var mediaItems: [JobMediaItem] = []

    init(jobNumber: Int = 0) {
        self.jobNumber = jobNumber
        self.mediaItems = []
    }

    var totalBF: Double { lines.reduce(0) { $0 + $1.totalBF } }
    var totalPieces: Int { lines.reduce(0) { $0 + (Int($1.quantity.filter { $0.isNumber }) ?? 0) } }
    /// Milling labor only, before mobilization fees.
    var millingSubtotal: Double { lines.reduce(0) { $0 + $1.lineTotal } }
    var mobilizationTotal: Double {
        (sawmillMobilization ? Self.mobilizationFee : 0)
            + (skidSteerMobilization ? Self.mobilizationFee : 0)
    }
    var totalPrice: Double { millingSubtotal + mobilizationTotal }

    var jobID: String { String(format: "MILL-%04d", jobNumber) }

    // Custom decoding so jobs saved before the newer fields existed
    // still load (their keys are simply absent from the old JSON).
    enum CodingKeys: String, CodingKey {
        case id, jobNumber, customerName, date, notes, completed
        case sawmillMobilization, skidSteerMobilization, lines
        case mediaItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        jobNumber = try container.decodeIfPresent(Int.self, forKey: .jobNumber) ?? 0
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? ""
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        sawmillMobilization = try container.decodeIfPresent(Bool.self, forKey: .sawmillMobilization) ?? false
        skidSteerMobilization = try container.decodeIfPresent(Bool.self, forKey: .skidSteerMobilization) ?? false
        lines = try container.decodeIfPresent([MillingLine].self, forKey: .lines) ?? []
        mediaItems = try container.decodeIfPresent([JobMediaItem].self, forKey: .mediaItems) ?? []
    }
}

// MARK: - Storage

enum MillingJobStorage {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("milling_jobs", isDirectory: true)
    }

    static func loadAll() -> [MillingJob] {
        ensureDir()
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var jobs: [MillingJob] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: url),
               var job = try? JSONDecoder().decode(MillingJob.self, from: data) {
                // Load media for this job
                job.mediaItems = JobMediaStorage.loadMedia(jobID: job.id, jobType: .milling)
                jobs.append(job)
            }
        }
        return jobs.sorted { $0.date > $1.date }
    }

    static func save(_ job: MillingJob) {
        ensureDir()
        let fileURL = dir.appendingPathComponent(filename(for: job))
        guard let data = try? JSONEncoder().encode(job) else { return }
        do {
            try data.write(to: fileURL, options: [.atomic])
            applyFileProtection(fileURL)
            // Save media files
            JobMediaStorage.saveMedia(job.mediaItems, jobID: job.id, jobType: .milling)
        } catch {}
    }

    static func delete(_ job: MillingJob) {
        ensureDir()
        let prefix = job.id.uuidString
        if let url = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent.hasPrefix(prefix) }) {
            try? FileManager.default.removeItem(at: url)
        }
        // Delete associated media
        JobMediaStorage.deleteAllMedia(jobID: job.id, jobType: .milling)
    }

    private static func filename(for job: MillingJob) -> String {
        let stem = job.customerName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        let safe = stem.isEmpty ? "Milling-Job" : stem
        return "\(job.id.uuidString)-\(Int(job.date.timeIntervalSince1970))-\(safe).json"
    }

    private static func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

// MARK: - Views

struct MillingJobsView: View {
    @State private var jobs: [MillingJob] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if jobs.isEmpty {
                ContentUnavailableView {
                    Label("No Milling Jobs", systemImage: "tree.fill")
                } description: {
                    Text("Tap + to inventory boards milled from customer-supplied logs.")
                }
            } else {
                List {
                    ForEach($jobs) { $job in
                        NavigationLink {
                            MillingJobDetailView(job: $job)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(job.customerName.isEmpty ? "New Milling Job" : job.customerName)
                                            .font(.headline)
                                        if job.completed {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.subheadline)
                                        }
                                    }
                                    Text("\(job.jobID) · \(job.totalPieces) pcs · \(job.totalBF.formatted(.number.precision(.fractionLength(0...2)))) BF · \(job.date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(currencyString(job.totalPrice))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .onDelete { offsets in
                        let toDelete = offsets.map { jobs[$0] }
                        for job in toDelete {
                            MillingJobStorage.delete(job)
                        }
                        jobs.remove(atOffsets: offsets)
                    }
                }
            }
        }
        .navigationTitle("Customer Logs Milled")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    jobs.insert(MillingJob(jobNumber: (jobs.map(\.jobNumber).max() ?? 0) + 1), at: 0)
                } label: {
                    Label("New Job", systemImage: "plus")
                }
            }
        }
        .onAppear {
            if !loaded {
                jobs = MillingJobStorage.loadAll()
                assignMissingJobNumbers()
                loaded = true
            }
        }
        .onChange(of: jobs) { _, newValue in
            for job in newValue { MillingJobStorage.save(job) }
        }
    }

    /// Gives jobs saved before job IDs existed a number, oldest first, so
    /// numbering roughly follows the order the work was done.
    private func assignMissingJobNumbers() {
        var next = jobs.map(\.jobNumber).max() ?? 0
        for index in jobs.indices.reversed() where jobs[index].jobNumber == 0 {
            next += 1
            jobs[index].jobNumber = next
            MillingJobStorage.save(jobs[index])
        }
    }
}

private struct MillingJobDetailView: View {
    @Binding var job: MillingJob
    @State private var draft = MillingLine()
    @State private var reportURL: URL?

    var body: some View {
        Form {
            Section("Customer") {
                LabeledContent("Job ID", value: job.jobID)
                CustomerSuggestionField(title: "Customer", name: $job.customerName) { _ in }
                DatePicker("Date", selection: $job.date, displayedComponents: .date)
                TextField("Notes", text: $job.notes, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section {
                Toggle(isOn: $job.sawmillMobilization) {
                    LabeledContent("Sawmill Mobilization",
                                   value: currencyString(MillingJob.mobilizationFee))
                }
                Toggle(isOn: $job.skidSteerMobilization) {
                    LabeledContent("Skid Steer Mobilization",
                                   value: currencyString(MillingJob.mobilizationFee))
                }
            } header: {
                Text("Mobilization Fees")
            } footer: {
                Text("Flat charge per machine hauled to the job site, added to the job total.")
            }

            Section {
                Toggle("Job Completed", isOn: $job.completed)
                if job.completed {
                    Button {
                        reportURL = MillingReport.customerLumberReport(for: job)
                    } label: {
                        Label("Send Customer Lumber Report", systemImage: "square.and.arrow.up")
                            .font(.headline)
                    }
                    .disabled(job.lines.isEmpty)
                }
            } header: {
                Text("Status")
            } footer: {
                if job.completed {
                    Text("Generates a PDF with every board, totals, and the milling charge — share it straight from the preview.")
                }
            }

            Section {
                NavigationLink {
                    JobMediaGalleryView(
                        jobID: job.id,
                        jobType: .milling,
                        mediaItems: Binding(
                            get: { job.mediaItems },
                            set: { 
                                job.mediaItems = $0
                                MillingJobStorage.save(job)
                            }
                        )
                    )
                } label: {
                    HStack {
                        Label("Job Photos & Videos", systemImage: "photo.on.rectangle")
                        Spacer()
                        if !job.mediaItems.isEmpty {
                            Text("\(job.mediaItems.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } footer: {
                Text("Document this milling job with before and after photos or videos.")
            }

            Section("Add Line") {
                CutFields(line: Binding(get: { CutLine(species: draft.species,
                                                       sizeType: draft.sizeType,
                                                       thicknessIn: draft.thicknessIn,
                                                       widthIn: draft.widthIn,
                                                       lengthFt: draft.lengthFt,
                                                       quantity: draft.quantity) },
                                        set: { new in
                                            draft.species = new.species
                                            draft.sizeType = new.sizeType
                                            draft.thicknessIn = new.thicknessIn
                                            draft.widthIn = new.widthIn
                                            draft.lengthFt = new.lengthFt
                                            draft.quantity = new.quantity
                                        }))
                Text("≈ \(draft.bfPerPiece.formatted(.number.precision(.fractionLength(0...2)))) BF each · \(currencyString(draft.ratePerBF))/BF = \(currencyString(draft.lineTotal))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    job.lines.append(draft)
                    draft = MillingLine()
                } label: {
                    Label("Add to Job", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Section("Lines") {
                if job.lines.isEmpty {
                    Text("No lines yet.").foregroundStyle(.secondary)
                } else {
                    ForEach($job.lines) { $line in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(line.species.displayName) \(line.thicknessIn)×\(line.widthIn)×\(line.lengthFt)ft")
                                Spacer()
                                Text(currencyString(line.lineTotal))
                                    .font(.subheadline.weight(.semibold))
                            }
                            HStack {
                                Text("Qty")
                                    .foregroundStyle(.secondary)
                                SelectAllTextField(placeholder: "1", text: $line.quantity, keyboard: .numberPad)
                                    .frame(maxWidth: 60)
                                Spacer()
                                Text("\(line.totalBF.formatted(.number.precision(.fractionLength(0...2)))) BF · \(currencyString(line.ratePerBF))/BF")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { job.lines.remove(atOffsets: $0) }
                    LabeledContent("Total Board Feet", value: job.totalBF.formatted(.number.precision(.fractionLength(0...2))))
                    if job.mobilizationTotal > 0 {
                        LabeledContent("Milling Subtotal", value: currencyString(job.millingSubtotal))
                        LabeledContent("Mobilization Fees", value: currencyString(job.mobilizationTotal))
                    }
                    LabeledContent("Total", value: currencyString(job.totalPrice))
                        .font(.headline)
                }
            }
        }
        .navigationTitle(job.customerName.isEmpty ? "Milling Job" : job.customerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .sheet(isPresented: .init(
            get: { reportURL != nil },
            set: { if !$0 { reportURL = nil } }
        )) {
            if let reportURL {
                PDFPreviewSheet(url: reportURL, title: "Lumber Report")
            }
        }
    }
}

#Preview {
    NavigationStack { MillingJobsView() }
}
