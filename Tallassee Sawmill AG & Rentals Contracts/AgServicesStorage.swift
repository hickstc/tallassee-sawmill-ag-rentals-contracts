import Foundation

struct AgServicesRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var signedAt: Date? = nil
    var data: AgServicesData

    var customerName: String { data.customerName }
}

enum AgServicesStorage {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ag_services", isDirectory: true)
    }

    static func loadAll() -> [AgServicesRecord] {
        ensureDir()
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var records: [AgServicesRecord] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: url),
               var rec = try? JSONDecoder().decode(AgServicesRecord.self, from: data) {
                // Load media for this record
                rec.data.mediaItems = JobMediaStorage.loadMedia(jobID: rec.id, jobType: .agServices)
                records.append(rec)
            }
        }
        // Newest first
        return records.sorted { ($0.updatedAt, $0.createdAt) > ($1.updatedAt, $1.createdAt) }
    }

    static func save(_ record: AgServicesRecord) {
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
            // Save media files
            JobMediaStorage.saveMedia(rec.data.mediaItems, jobID: rec.id, jobType: .agServices)
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
        // Delete associated media
        JobMediaStorage.deleteAllMedia(jobID: id, jobType: .agServices)
    }

    private static func filename(for rec: AgServicesRecord) -> String {
        let stem = rec.customerName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        let safe = stem.isEmpty ? "Ag-Services" : stem
        return "\(rec.id.uuidString)-\(Int(rec.createdAt.timeIntervalSince1970))-\(safe).json"
    }

    private static func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private static func applyFileProtection(_ url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}
