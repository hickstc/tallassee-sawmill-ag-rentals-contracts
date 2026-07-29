//
//  MaintenanceBackup.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Backup and restore for the maintenance database. Exports every entity —
//  machines, photos, parts, purchases, kits, tasks, service history, and
//  attachments — to a single versioned JSON file (binary data is base64),
//  and restores by replacing the current maintenance data.
//

import Foundation
import SwiftData

// MARK: - Backup document

/// The on-disk backup format. `version` allows future format migrations.
struct MaintenanceBackup: Codable {
    var version = 1
    var exportedAt = Date()

    var equipment: [EquipmentDTO] = []
    var photos: [PhotoDTO] = []
    var parts: [PartDTO] = []
    var purchases: [PurchaseDTO] = []
    var equipmentParts: [EquipmentPartDTO] = []
    var kits: [KitDTO] = []
    var kitItems: [KitItemDTO] = []
    var tasks: [TaskDTO] = []
    var logs: [LogDTO] = []
    var usages: [UsageDTO] = []
    var attachments: [AttachmentDTO] = []
    /// Optional so version-1 backups made before the scheduler still decode.
    var scheduledJobs: [JobDTO]? = nil

    // Entities reference each other by UUID, mirroring the SwiftData graph.

    struct JobDTO: Codable {
        var uuid: UUID
        var jobNumber: Int
        var customer: String
        var type: String
        var date: Date
        var durationMinutes: Int
        var address: String
        var phone: String
        var notes: String
        var status: String
        var createdAt: Date
    }

    struct EquipmentDTO: Codable {
        var uuid: UUID
        var name: String
        var category: String
        var make: String
        var model: String
        var year: Int?
        var serialOrVIN: String
        var purchaseDate: Date?
        var purchasePrice: Decimal?
        var meterType: String
        var currentMeter: Double
        var notes: String
        var createdAt: Date
    }

    struct PhotoDTO: Codable {
        var uuid: UUID
        var imageData: Data
        var caption: String
        var createdAt: Date
        var equipmentUUID: UUID?
    }

    struct PartDTO: Codable {
        var uuid: UUID
        var kind: String
        var category: String
        var oemNumber: String
        var partDescription: String
        var crossRefs: String
        var preferredSupplier: String
        var lastPrice: Decimal?
        var notes: String
        var orderLink: String
        var quantityOnHand: Double
        var unit: String
        var lowStockThreshold: Double
        var createdAt: Date
    }

    struct PurchaseDTO: Codable {
        var uuid: UUID
        var date: Date
        var supplier: String
        var quantity: Double
        var unitPrice: Decimal?
        var notes: String
        var partUUID: UUID?
    }

    struct EquipmentPartDTO: Codable {
        var uuid: UUID
        var usageNote: String
        var quantity: Int
        var equipmentUUID: UUID?
        var partUUID: UUID?
    }

    struct KitDTO: Codable {
        var uuid: UUID
        var name: String
        var notes: String
        var createdAt: Date
    }

    struct KitItemDTO: Codable {
        var uuid: UUID
        var quantity: Double
        var partName: String
        var partUUID: UUID?
        var kitUUID: UUID?
    }

    struct TaskDTO: Codable {
        var uuid: UUID
        var name: String
        var intervalMeter: Double?
        var intervalDays: Int?
        var lastDoneDate: Date?
        var lastDoneMeter: Double?
        var reminderEnabled: Bool
        var reminderLeadDays: Int
        var notes: String
        var createdAt: Date
        var equipmentUUID: UUID?
        var defaultKitUUID: UUID?
    }

    struct LogDTO: Codable {
        var uuid: UUID
        var date: Date
        var meterAtService: Double?
        var cost: Decimal?
        var performedBy: String
        var notes: String
        var taskUUID: UUID?
    }

    struct UsageDTO: Codable {
        var uuid: UUID
        var quantity: Double
        var partName: String
        var partUUID: UUID?
        var logUUID: UUID?
    }

    struct AttachmentDTO: Codable {
        var uuid: UUID
        var kind: String
        var fileName: String
        var data: Data
        var createdAt: Date
        var equipmentUUID: UUID?
        var logUUID: UUID?
    }
}

// MARK: - Backup manager

@MainActor
enum MaintenanceBackupManager {

    enum BackupError: LocalizedError {
        case unreadableFile
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "The file could not be read as a maintenance backup."
            case .unsupportedVersion(let version):
                return "This backup was made by a newer app version (format \(version))."
            }
        }
    }

    // MARK: Export

    /// Snapshots the whole maintenance database into a JSON file in the
    /// temporary directory and returns its URL for sharing.
    static func export(context: ModelContext) throws -> URL {
        var backup = MaintenanceBackup()

        backup.equipment = try context.fetch(FetchDescriptor<Equipment>()).map {
            .init(uuid: $0.uuid, name: $0.name, category: $0.categoryRaw, make: $0.make,
                  model: $0.model, year: $0.year, serialOrVIN: $0.serialOrVIN,
                  purchaseDate: $0.purchaseDate, purchasePrice: $0.purchasePrice,
                  meterType: $0.meterTypeRaw, currentMeter: $0.currentMeter,
                  notes: $0.notes, createdAt: $0.createdAt)
        }
        backup.photos = try context.fetch(FetchDescriptor<EquipmentPhoto>()).map {
            .init(uuid: $0.uuid, imageData: $0.imageData, caption: $0.caption,
                  createdAt: $0.createdAt, equipmentUUID: $0.equipment?.uuid)
        }
        backup.parts = try context.fetch(FetchDescriptor<Part>()).map {
            .init(uuid: $0.uuid, kind: $0.kindRaw, category: $0.categoryRaw,
                  oemNumber: $0.oemNumber, partDescription: $0.partDescription,
                  crossRefs: $0.crossRefs, preferredSupplier: $0.preferredSupplier,
                  lastPrice: $0.lastPrice, notes: $0.notes, orderLink: $0.orderLink,
                  quantityOnHand: $0.quantityOnHand, unit: $0.unit,
                  lowStockThreshold: $0.lowStockThreshold, createdAt: $0.createdAt)
        }
        backup.purchases = try context.fetch(FetchDescriptor<PartPurchase>()).map {
            .init(uuid: $0.uuid, date: $0.date, supplier: $0.supplier,
                  quantity: $0.quantity, unitPrice: $0.unitPrice, notes: $0.notes,
                  partUUID: $0.part?.uuid)
        }
        backup.equipmentParts = try context.fetch(FetchDescriptor<EquipmentPart>()).map {
            .init(uuid: $0.uuid, usageNote: $0.usageNote, quantity: $0.quantity,
                  equipmentUUID: $0.equipment?.uuid, partUUID: $0.part?.uuid)
        }
        backup.kits = try context.fetch(FetchDescriptor<ServiceKit>()).map {
            .init(uuid: $0.uuid, name: $0.name, notes: $0.notes, createdAt: $0.createdAt)
        }
        backup.kitItems = try context.fetch(FetchDescriptor<ServiceKitItem>()).map {
            .init(uuid: $0.uuid, quantity: $0.quantity, partName: $0.partName,
                  partUUID: $0.part?.uuid, kitUUID: $0.kit?.uuid)
        }
        backup.tasks = try context.fetch(FetchDescriptor<MaintenanceTask>()).map {
            .init(uuid: $0.uuid, name: $0.name, intervalMeter: $0.intervalMeter,
                  intervalDays: $0.intervalDays, lastDoneDate: $0.lastDoneDate,
                  lastDoneMeter: $0.lastDoneMeter, reminderEnabled: $0.reminderEnabled,
                  reminderLeadDays: $0.reminderLeadDays, notes: $0.notes,
                  createdAt: $0.createdAt, equipmentUUID: $0.equipment?.uuid,
                  defaultKitUUID: $0.defaultKit?.uuid)
        }
        backup.logs = try context.fetch(FetchDescriptor<MaintenanceLog>()).map {
            .init(uuid: $0.uuid, date: $0.date, meterAtService: $0.meterAtService,
                  cost: $0.cost, performedBy: $0.performedBy, notes: $0.notes,
                  taskUUID: $0.task?.uuid)
        }
        backup.usages = try context.fetch(FetchDescriptor<ServicePartUsage>()).map {
            .init(uuid: $0.uuid, quantity: $0.quantity, partName: $0.partName,
                  partUUID: $0.part?.uuid, logUUID: $0.log?.uuid)
        }
        backup.attachments = try context.fetch(FetchDescriptor<MaintenanceAttachment>()).map {
            .init(uuid: $0.uuid, kind: $0.kindRaw, fileName: $0.fileName, data: $0.data,
                  createdAt: $0.createdAt, equipmentUUID: $0.equipment?.uuid,
                  logUUID: $0.log?.uuid)
        }
        backup.scheduledJobs = try context.fetch(FetchDescriptor<ScheduledJob>()).map {
            .init(uuid: $0.uuid, jobNumber: $0.jobNumber, customer: $0.customer,
                  type: $0.typeRaw, date: $0.date, durationMinutes: $0.durationMinutes,
                  address: $0.address, phone: $0.phone, notes: $0.notes,
                  status: $0.statusRaw, createdAt: $0.createdAt)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tallassee-Maintenance-Backup-\(stamp).json")
        try data.write(to: url, options: [.atomic])
        applyFileProtection(url)
        return url
    }

    // MARK: Restore

    /// Replaces all maintenance data with the backup's contents and returns a
    /// human-readable summary. The caller confirms with the user beforehand.
    @discardableResult
    static func restore(from url: URL, context: ModelContext) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw BackupError.unreadableFile
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: MaintenanceBackup
        do {
            backup = try decoder.decode(MaintenanceBackup.self, from: data)
        } catch {
            throw BackupError.unreadableFile
        }
        guard backup.version <= 1 else {
            throw BackupError.unsupportedVersion(backup.version)
        }

        try deleteAllMaintenanceData(context: context)

        // Rebuild the graph: standalone entities first, then everything that
        // references them, resolving by UUID.
        var equipmentByUUID: [UUID: Equipment] = [:]
        for dto in backup.equipment {
            let machine = Equipment(
                name: dto.name,
                category: EquipmentCategory(rawValue: dto.category) ?? .other,
                make: dto.make, model: dto.model, year: dto.year,
                serialOrVIN: dto.serialOrVIN, purchaseDate: dto.purchaseDate,
                purchasePrice: dto.purchasePrice,
                meterType: MeterType(rawValue: dto.meterType) ?? .hours,
                currentMeter: dto.currentMeter, notes: dto.notes
            )
            machine.uuid = dto.uuid
            machine.createdAt = dto.createdAt
            context.insert(machine)
            equipmentByUUID[dto.uuid] = machine
        }

        var partsByUUID: [UUID: Part] = [:]
        for dto in backup.parts {
            let part = Part(
                kind: PartKind(rawValue: dto.kind) ?? .part,
                oemNumber: dto.oemNumber, partDescription: dto.partDescription,
                crossRefs: dto.crossRefs, preferredSupplier: dto.preferredSupplier,
                lastPrice: dto.lastPrice, notes: dto.notes, orderLink: dto.orderLink,
                quantityOnHand: dto.quantityOnHand, unit: dto.unit,
                lowStockThreshold: dto.lowStockThreshold
            )
            part.uuid = dto.uuid
            part.categoryRaw = dto.category
            part.createdAt = dto.createdAt
            context.insert(part)
            partsByUUID[dto.uuid] = part
        }

        var kitsByUUID: [UUID: ServiceKit] = [:]
        for dto in backup.kits {
            let kit = ServiceKit(name: dto.name, notes: dto.notes)
            kit.uuid = dto.uuid
            kit.createdAt = dto.createdAt
            context.insert(kit)
            kitsByUUID[dto.uuid] = kit
        }

        for dto in backup.photos {
            let photo = EquipmentPhoto(imageData: dto.imageData, caption: dto.caption)
            photo.uuid = dto.uuid
            photo.createdAt = dto.createdAt
            photo.equipment = dto.equipmentUUID.flatMap { equipmentByUUID[$0] }
            context.insert(photo)
        }

        for dto in backup.purchases {
            let purchase = PartPurchase(date: dto.date, supplier: dto.supplier,
                                        quantity: dto.quantity, unitPrice: dto.unitPrice,
                                        notes: dto.notes)
            purchase.uuid = dto.uuid
            purchase.part = dto.partUUID.flatMap { partsByUUID[$0] }
            context.insert(purchase)
        }

        for dto in backup.equipmentParts {
            let link = EquipmentPart(usageNote: dto.usageNote, quantity: dto.quantity,
                                     equipment: dto.equipmentUUID.flatMap { equipmentByUUID[$0] },
                                     part: dto.partUUID.flatMap { partsByUUID[$0] })
            link.uuid = dto.uuid
            context.insert(link)
        }

        for dto in backup.kitItems {
            let item = ServiceKitItem(quantity: dto.quantity,
                                      part: dto.partUUID.flatMap { partsByUUID[$0] },
                                      kit: dto.kitUUID.flatMap { kitsByUUID[$0] })
            item.uuid = dto.uuid
            item.partName = dto.partName
            context.insert(item)
        }

        var tasksByUUID: [UUID: MaintenanceTask] = [:]
        for dto in backup.tasks {
            let task = MaintenanceTask(name: dto.name, intervalMeter: dto.intervalMeter,
                                       intervalDays: dto.intervalDays,
                                       lastDoneDate: dto.lastDoneDate,
                                       lastDoneMeter: dto.lastDoneMeter, notes: dto.notes,
                                       equipment: dto.equipmentUUID.flatMap { equipmentByUUID[$0] })
            task.uuid = dto.uuid
            task.reminderEnabled = dto.reminderEnabled
            task.reminderLeadDays = dto.reminderLeadDays
            task.createdAt = dto.createdAt
            task.defaultKit = dto.defaultKitUUID.flatMap { kitsByUUID[$0] }
            context.insert(task)
            tasksByUUID[dto.uuid] = task
        }

        var logsByUUID: [UUID: MaintenanceLog] = [:]
        for dto in backup.logs {
            let log = MaintenanceLog(date: dto.date, meterAtService: dto.meterAtService,
                                     cost: dto.cost, performedBy: dto.performedBy,
                                     notes: dto.notes,
                                     task: dto.taskUUID.flatMap { tasksByUUID[$0] })
            log.uuid = dto.uuid
            context.insert(log)
            logsByUUID[dto.uuid] = log
        }

        for dto in backup.usages {
            let usage = ServicePartUsage(quantity: dto.quantity,
                                         part: dto.partUUID.flatMap { partsByUUID[$0] },
                                         log: dto.logUUID.flatMap { logsByUUID[$0] })
            usage.uuid = dto.uuid
            usage.partName = dto.partName
            context.insert(usage)
        }

        for dto in backup.attachments {
            let attachment = MaintenanceAttachment(
                kind: AttachmentKind(rawValue: dto.kind) ?? .photo,
                fileName: dto.fileName, data: dto.data
            )
            attachment.uuid = dto.uuid
            attachment.createdAt = dto.createdAt
            attachment.equipment = dto.equipmentUUID.flatMap { equipmentByUUID[$0] }
            attachment.log = dto.logUUID.flatMap { logsByUUID[$0] }
            context.insert(attachment)
        }

        for dto in backup.scheduledJobs ?? [] {
            let job = ScheduledJob(jobNumber: dto.jobNumber, customer: dto.customer,
                                   type: JobType(rawValue: dto.type) ?? .other,
                                   date: dto.date, durationMinutes: dto.durationMinutes,
                                   address: dto.address, phone: dto.phone, notes: dto.notes)
            job.uuid = dto.uuid
            job.statusRaw = dto.status
            job.createdAt = dto.createdAt
            // Calendar event IDs are device-specific; a fresh sync recreates events.
            context.insert(job)
        }

        try context.save()

        // Reschedule reminders for the restored tasks.
        for task in tasksByUUID.values where task.reminderEnabled {
            ReminderScheduler.sync(task: task)
        }

        let exported = backup.exportedAt.formatted(date: .abbreviated, time: .shortened)
        return "Restored \(backup.equipment.count) machines, \(backup.parts.count) parts, "
            + "\(backup.kits.count) kits, and \(backup.logs.count) service records "
            + "from the backup made \(exported)."
    }

    private static func deleteAllMaintenanceData(context: ModelContext) throws {
        // Order doesn't matter for delete(model:); cascades are irrelevant
        // because every entity is removed explicitly.
        try context.delete(model: ScheduledJob.self)
        try context.delete(model: MaintenanceAttachment.self)
        try context.delete(model: ServicePartUsage.self)
        try context.delete(model: MaintenanceLog.self)
        try context.delete(model: MaintenanceTask.self)
        try context.delete(model: ServiceKitItem.self)
        try context.delete(model: ServiceKit.self)
        try context.delete(model: EquipmentPart.self)
        try context.delete(model: PartPurchase.self)
        try context.delete(model: Part.self)
        try context.delete(model: EquipmentPhoto.self)
        try context.delete(model: Equipment.self)
    }
}
