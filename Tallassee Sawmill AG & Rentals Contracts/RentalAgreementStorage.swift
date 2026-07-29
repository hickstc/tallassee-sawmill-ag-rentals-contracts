import Foundation

struct RentalAgreementRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var signedAt: Date? = nil
    var data: RentalAgreementData

    var customerName: String { data.lesseeName }
    
    // Hashable & Equatable based on id
    static func == (lhs: RentalAgreementRecord, rhs: RentalAgreementRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum RentalAgreementStorage {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("rental_agreements", isDirectory: true)
    }

    static func loadAll() -> [RentalAgreementRecord] {
        ensureDir()
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var records: [RentalAgreementRecord] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: url), let rec = try? JSONDecoder().decode(RentalAgreementRecord.self, from: data) {
                records.append(rec)
            }
        }
        return records.sorted { ($0.updatedAt, $0.createdAt) > ($1.updatedAt, $1.createdAt) }
    }

    static func save(_ record: RentalAgreementRecord) {
        ensureDir()
        var rec = record
        rec.updatedAt = Date()
        let name = filename(for: rec)
        // Remove stale copies of this record saved under an older customer name.
        if let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in urls where url.lastPathComponent.hasPrefix(rec.id.uuidString) && url.lastPathComponent != name {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let fileURL = dir.appendingPathComponent(name)
        guard let data = try? JSONEncoder().encode(rec) else { return }
        do {
            try data.write(to: fileURL, options: [.atomic])
            applyFileProtection(fileURL)
        } catch {
            // ignore
        }
    }

    static func delete(id: UUID) {
        ensureDir()
        let prefix = id.uuidString
        if let url = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent.hasPrefix(prefix) }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func filename(for rec: RentalAgreementRecord) -> String {
        let stem = rec.customerName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        let safe = stem.isEmpty ? "Rental-Agreement" : stem
        return "\(rec.id.uuidString)-\(Int(rec.createdAt.timeIntervalSince1970))-\(safe).json"
    }

    private static func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
