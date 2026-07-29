//
//  MaintenanceModels.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  SwiftData models for the Fleet Maintenance module.
//
//  CloudKit-readiness: every attribute has a default value and every
//  relationship is optional, which is required before a schema can be
//  synced with CloudKit. No `.unique` attributes are used for the same
//  reason. See MaintenanceStore.swift for the sync switch.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Equipment Category

/// The kinds of machines the fleet tracks.
enum EquipmentCategory: String, CaseIterable, Identifiable {
    case trackLoader = "Track Loader"
    case excavator = "Excavator"
    case tractor = "Tractor"
    case sawmill = "Sawmill"
    case truck = "Truck"
    case trailer = "Trailer"
    case utvAtv = "UTV/ATV"
    case mower = "Mower"
    case chainsaw = "Chainsaw"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .trackLoader: return "gearshape.2.fill"
        case .excavator: return "wrench.and.screwdriver.fill"
        case .tractor: return "leaf.circle.fill"
        case .sawmill: return "tree.fill"
        case .truck: return "box.truck.fill"
        case .trailer: return "shippingbox.fill"
        case .utvAtv: return "car.2.fill"
        case .mower: return "scissors"
        case .chainsaw: return "bolt.fill"
        case .other: return "wrench.fill"
        }
    }
}

// MARK: - Meter Type

/// Whether a machine's usage is measured in engine hours or road miles.
enum MeterType: String, CaseIterable, Identifiable {
    case hours = "Hours"
    case miles = "Miles"

    var id: String { rawValue }

    var unitAbbreviation: String {
        switch self {
        case .hours: return "hrs"
        case .miles: return "mi"
        }
    }
}

// MARK: - Maintenance Status

/// Evaluated urgency of a maintenance item. Lower raw value = more urgent,
/// so `min()` over several checks yields the worst case.
enum MaintenanceStatus: Int, Comparable {
    case overdue = 0
    case dueSoon = 1
    case upToDate = 2
    case notScheduled = 3

    static func < (lhs: MaintenanceStatus, rhs: MaintenanceStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .overdue: return "Overdue"
        case .dueSoon: return "Due Soon"
        case .upToDate: return "Up to Date"
        case .notScheduled: return "No Schedule"
        }
    }

    var color: Color {
        switch self {
        case .overdue: return .red
        case .dueSoon: return .orange
        case .upToDate: return .green
        case .notScheduled: return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .overdue: return "exclamationmark.circle.fill"
        case .dueSoon: return "clock.fill"
        case .upToDate: return "checkmark.circle.fill"
        case .notScheduled: return "questionmark.circle"
        }
    }
}

// MARK: - Equipment

@Model
final class Equipment {
    /// Stable identifier used for notification identifiers etc.
    var uuid: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = EquipmentCategory.other.rawValue
    var make: String = ""
    var model: String = ""
    var year: Int? = nil
    var serialOrVIN: String = ""
    var purchaseDate: Date? = nil
    var purchasePrice: Decimal? = nil
    var meterTypeRaw: String = MeterType.hours.rawValue
    /// Current engine hours or mileage, per `meterType`.
    var currentMeter: Double = 0
    var notes: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \EquipmentPhoto.equipment)
    var photos: [EquipmentPhoto]? = nil

    @Relationship(deleteRule: .cascade, inverse: \EquipmentPart.equipment)
    var partLinks: [EquipmentPart]? = nil

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceTask.equipment)
    var tasks: [MaintenanceTask]? = nil

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceAttachment.equipment)
    var attachments: [MaintenanceAttachment]? = nil

    init(
        name: String = "",
        category: EquipmentCategory = .other,
        make: String = "",
        model: String = "",
        year: Int? = nil,
        serialOrVIN: String = "",
        purchaseDate: Date? = nil,
        purchasePrice: Decimal? = nil,
        meterType: MeterType = .hours,
        currentMeter: Double = 0,
        notes: String = ""
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.make = make
        self.model = model
        self.year = year
        self.serialOrVIN = serialOrVIN
        self.purchaseDate = purchaseDate
        self.purchasePrice = purchasePrice
        self.meterTypeRaw = meterType.rawValue
        self.currentMeter = currentMeter
        self.notes = notes
    }

    var category: EquipmentCategory {
        get { EquipmentCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var meterType: MeterType {
        get { MeterType(rawValue: meterTypeRaw) ?? .hours }
        set { meterTypeRaw = newValue.rawValue }
    }

    /// Photos in user-defined order; the first one is the primary photo.
    var sortedPhotos: [EquipmentPhoto] {
        (photos ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var sortedPartLinks: [EquipmentPart] {
        (partLinks ?? []).sorted {
            ($0.part?.partDescription ?? "") < ($1.part?.partDescription ?? "")
        }
    }

    var sortedTasks: [MaintenanceTask] {
        (tasks ?? []).sorted { $0.name < $1.name }
    }

    var primaryPhotoData: Data? { sortedPhotos.first?.imageData }

    /// "1,234 hrs" or "56,789 mi" for list rows.
    var meterSummary: String {
        "\(currentMeter.formatted(.number.precision(.fractionLength(0...1)))) \(meterType.unitAbbreviation)"
    }

    /// Worst status across this machine's maintenance items — drives row color coding.
    var worstStatus: MaintenanceStatus {
        (tasks ?? []).map { $0.status() }.min() ?? .notScheduled
    }
}

// MARK: - Equipment Photo

@Model
final class EquipmentPhoto {
    var uuid: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data = Data()
    var caption: String = ""
    var createdAt: Date = Date()
    var equipment: Equipment? = nil

    init(imageData: Data, caption: String = "") {
        self.imageData = imageData
        self.caption = caption
    }
}

// MARK: - Part (master parts library)

/// Whether a library entry is a hard part (filter, belt) or a fluid (oil, coolant).
enum PartKind: String, CaseIterable, Identifiable {
    case part = "Part"
    case fluid = "Fluid"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .part: return "gearshape.fill"
        case .fluid: return "drop.fill"
        }
    }
}

/// Functional grouping for browsing the master library.
enum PartCategory: String, CaseIterable, Identifiable {
    case filters = "Filters"
    case beltsHoses = "Belts & Hoses"
    case electrical = "Batteries & Electrical"
    case engine = "Engine"
    case hydraulic = "Hydraulic"
    case undercarriage = "Undercarriage & Tires"
    case cutting = "Blades & Cutting"
    case fluids = "Fluids & Lubricants"
    case other = "Other"

    var id: String { rawValue }
}

@Model
final class Part {
    var uuid: UUID = UUID()
    var kindRaw: String = PartKind.part.rawValue
    var categoryRaw: String = PartCategory.other.rawValue
    /// Manufacturer part number, e.g. "V0531-43150".
    var oemNumber: String = ""
    var partDescription: String = ""
    /// Comma-separated aftermarket cross-reference numbers.
    var crossRefs: String = ""
    var preferredSupplier: String = ""
    var lastPrice: Decimal? = nil
    var notes: String = ""
    /// Optional URL for reordering (supplier product page).
    var orderLink: String = ""
    /// Stock on hand, in `unit`s. Fluids can be fractional (e.g. 2.5 gal).
    var quantityOnHand: Double = 0
    /// Stocking unit: "ea" for parts, "qt"/"gal" for fluids, etc.
    var unit: String = "ea"
    /// Warn when stock falls to this level. 0 = low-stock warnings off.
    var lowStockThreshold: Double = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \EquipmentPart.part)
    var equipmentLinks: [EquipmentPart]? = nil

    @Relationship(deleteRule: .cascade, inverse: \PartPurchase.part)
    var purchases: [PartPurchase]? = nil

    /// Kept when the part is deleted (nullified) so service history stays intact.
    @Relationship(deleteRule: .nullify, inverse: \ServicePartUsage.part)
    var serviceUsages: [ServicePartUsage]? = nil

    /// Kit lines referencing this part (nullified on delete; kits keep the row).
    @Relationship(deleteRule: .nullify, inverse: \ServiceKitItem.part)
    var kitItems: [ServiceKitItem]? = nil

    init(
        kind: PartKind = .part,
        oemNumber: String = "",
        partDescription: String = "",
        crossRefs: String = "",
        preferredSupplier: String = "",
        lastPrice: Decimal? = nil,
        notes: String = "",
        orderLink: String = "",
        quantityOnHand: Double = 0,
        unit: String = "ea",
        lowStockThreshold: Double = 0
    ) {
        self.kindRaw = kind.rawValue
        self.oemNumber = oemNumber
        self.partDescription = partDescription
        self.crossRefs = crossRefs
        self.preferredSupplier = preferredSupplier
        self.lastPrice = lastPrice
        self.notes = notes
        self.orderLink = orderLink
        self.quantityOnHand = quantityOnHand
        self.unit = unit
        self.lowStockThreshold = lowStockThreshold
    }

    var kind: PartKind {
        get { PartKind(rawValue: kindRaw) ?? .part }
        set { kindRaw = newValue.rawValue }
    }

    var category: PartCategory {
        get { PartCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// OEM number normalized for duplicate detection (case/whitespace/dashes ignored).
    var normalizedOEM: String {
        oemNumber
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Case-insensitive match on OEM number, cross refs, description, or supplier.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return oemNumber.localizedCaseInsensitiveContains(query)
            || crossRefs.localizedCaseInsensitiveContains(query)
            || partDescription.localizedCaseInsensitiveContains(query)
            || preferredSupplier.localizedCaseInsensitiveContains(query)
    }

    var orderURL: URL? {
        guard !orderLink.isEmpty else { return nil }
        return URL(string: orderLink)
    }

    /// True when a threshold is set and stock has fallen to (or below) it.
    var isLowStock: Bool {
        lowStockThreshold > 0 && quantityOnHand <= lowStockThreshold
    }

    /// "3 ea" / "2.5 gal" for rows and reports.
    var stockSummary: String {
        "\(quantityOnHand.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    var sortedPurchases: [PartPurchase] {
        (purchases ?? []).sorted { $0.date > $1.date }
    }

    /// Names of machines this part is linked to, for catalogs and detail screens.
    var usedOnNames: [String] {
        (equipmentLinks ?? []).compactMap { $0.equipment?.name }.sorted()
    }
}

// MARK: - Part Purchase

/// One purchase of a part or fluid — builds the price/supplier history.
@Model
final class PartPurchase {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var supplier: String = ""
    var quantity: Double = 1
    var unitPrice: Decimal? = nil
    var notes: String = ""
    var part: Part? = nil

    init(
        date: Date = Date(),
        supplier: String = "",
        quantity: Double = 1,
        unitPrice: Decimal? = nil,
        notes: String = ""
    ) {
        self.date = date
        self.supplier = supplier
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.notes = notes
    }

    var totalCost: Decimal? {
        guard let unitPrice else { return nil }
        return unitPrice * Decimal(quantity)
    }
}

// MARK: - Service Kit

/// A named bundle of parts/fluids for one job — e.g. "SVL75 250-hr service":
/// oil filter ×1, engine oil ×9 qt. Applying a kit when completing a service
/// fills in the consumed quantities in one tap.
@Model
final class ServiceKit {
    var uuid: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ServiceKitItem.kit)
    var items: [ServiceKitItem]? = nil

    /// Tasks that use this kit by default (nullified if the kit is deleted).
    @Relationship(deleteRule: .nullify, inverse: \MaintenanceTask.defaultKit)
    var tasks: [MaintenanceTask]? = nil

    init(name: String = "", notes: String = "") {
        self.name = name
        self.notes = notes
    }

    var sortedItems: [ServiceKitItem] {
        (items ?? []).sorted { $0.displayName < $1.displayName }
    }

    /// Kit lines that can't be filled from current stock.
    var shortItems: [ServiceKitItem] {
        sortedItems.filter { item in
            guard let part = item.part else { return true } // part deleted
            return part.quantityOnHand < item.quantity
        }
    }

    /// True when every line can be filled from stock.
    var isReady: Bool { !(items ?? []).isEmpty && shortItems.isEmpty }
}

/// One line of a service kit: a part and how much of it the job uses.
@Model
final class ServiceKitItem {
    var uuid: UUID = UUID()
    var quantity: Double = 1
    /// Snapshot of the part name so the kit stays readable if the part is deleted.
    var partName: String = ""
    var part: Part? = nil
    var kit: ServiceKit? = nil

    init(quantity: Double = 1, part: Part? = nil, kit: ServiceKit? = nil) {
        self.quantity = quantity
        self.partName = part?.partDescription ?? ""
        self.part = part
        self.kit = kit
    }

    var displayName: String {
        part?.partDescription ?? (partName.isEmpty ? "Deleted part" : partName)
    }
}

// MARK: - Service Part Usage

/// A part/fluid consumed by one service log — drives auto inventory decrement.
@Model
final class ServicePartUsage {
    var uuid: UUID = UUID()
    var quantity: Double = 1
    /// Snapshot of the part name so history survives part deletion.
    var partName: String = ""
    var part: Part? = nil
    var log: MaintenanceLog? = nil

    init(quantity: Double = 1, part: Part? = nil, log: MaintenanceLog? = nil) {
        self.quantity = quantity
        self.partName = part?.partDescription ?? ""
        self.part = part
        self.log = log
    }

    var displayName: String {
        part?.partDescription ?? (partName.isEmpty ? "Deleted part" : partName)
    }
}

// MARK: - Equipment ↔ Part link

/// Joins a machine to a part in the master library, with per-machine context
/// (e.g. the same battery part used on two machines with different quantities).
@Model
final class EquipmentPart {
    var uuid: UUID = UUID()
    /// Where/how the part is used on this machine, e.g. "Engine — outer element".
    var usageNote: String = ""
    var quantity: Int = 1
    var equipment: Equipment? = nil
    var part: Part? = nil

    init(usageNote: String = "", quantity: Int = 1, equipment: Equipment? = nil, part: Part? = nil) {
        self.usageNote = usageNote
        self.quantity = quantity
        self.equipment = equipment
        self.part = part
    }
}

// MARK: - Maintenance Task

/// A recurring maintenance item (e.g. "Engine oil & filter — every 250 hrs").
@Model
final class MaintenanceTask {
    /// "Due soon" window: within this many days of the due date.
    static let dueSoonWindowDays = 14
    /// "Due soon" window: within this many meter units (hours/miles) of the due reading.
    static let dueSoonWindowMeter: Double = 25

    var uuid: UUID = UUID()
    var name: String = ""
    /// Service interval in meter units (hours or miles). nil = not meter-based.
    var intervalMeter: Double? = nil
    /// Service interval in calendar days. nil = not date-based.
    var intervalDays: Int? = nil
    var lastDoneDate: Date? = nil
    var lastDoneMeter: Double? = nil
    var reminderEnabled: Bool = false
    /// How many days before the due date the local notification fires.
    var reminderLeadDays: Int = 7
    var notes: String = ""
    var createdAt: Date = Date()
    var equipment: Equipment? = nil

    /// Kit whose quantities prefill the Complete Service sheet for this task.
    var defaultKit: ServiceKit? = nil

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceLog.task)
    var logs: [MaintenanceLog]? = nil

    init(
        name: String = "",
        intervalMeter: Double? = nil,
        intervalDays: Int? = nil,
        lastDoneDate: Date? = nil,
        lastDoneMeter: Double? = nil,
        notes: String = "",
        equipment: Equipment? = nil
    ) {
        self.name = name
        self.intervalMeter = intervalMeter
        self.intervalDays = intervalDays
        self.lastDoneDate = lastDoneDate
        self.lastDoneMeter = lastDoneMeter
        self.notes = notes
        self.equipment = equipment
    }

    var sortedLogs: [MaintenanceLog] {
        (logs ?? []).sorted { $0.date > $1.date }
    }

    /// Next calendar due date, if the task is date-based and has a baseline.
    var nextDueDate: Date? {
        guard let intervalDays, let lastDoneDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: lastDoneDate)
    }

    /// Next due meter reading, if the task is meter-based and has a baseline.
    var nextDueMeter: Double? {
        guard let intervalMeter, let lastDoneMeter else { return nil }
        return lastDoneMeter + intervalMeter
    }

    /// Evaluates urgency from both the calendar and the meter; the worse one wins.
    /// A task with an interval but no "last done" baseline reports Due Soon so it
    /// surfaces on the dashboard until a first service is recorded.
    func status(asOf now: Date = .now) -> MaintenanceStatus {
        var results: [MaintenanceStatus] = []

        if intervalDays != nil {
            if let due = nextDueDate {
                if due <= now {
                    results.append(.overdue)
                } else if let window = Calendar.current.date(
                    byAdding: .day, value: Self.dueSoonWindowDays, to: now
                ), due <= window {
                    results.append(.dueSoon)
                } else {
                    results.append(.upToDate)
                }
            } else {
                results.append(.dueSoon) // never serviced yet
            }
        }

        if intervalMeter != nil {
            if let dueMeter = nextDueMeter {
                let current = equipment?.currentMeter ?? 0
                if current >= dueMeter {
                    results.append(.overdue)
                } else if dueMeter - current <= Self.dueSoonWindowMeter {
                    results.append(.dueSoon)
                } else {
                    results.append(.upToDate)
                }
            } else {
                results.append(.dueSoon) // never serviced yet
            }
        }

        return results.min() ?? .notScheduled
    }

    /// One-line "when is this due" summary for rows, e.g.
    /// "Due Aug 12 · Due at 1,250 hrs".
    var dueSummary: String {
        var pieces: [String] = []
        if let date = nextDueDate {
            pieces.append("Due \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        if let meter = nextDueMeter {
            let unit = equipment?.meterType.unitAbbreviation ?? MeterType.hours.unitAbbreviation
            pieces.append("Due at \(meter.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
        }
        if pieces.isEmpty {
            if intervalDays != nil || intervalMeter != nil {
                return "Not serviced yet"
            }
            return "No schedule set"
        }
        return pieces.joined(separator: " · ")
    }
}

// MARK: - Maintenance Log

/// A completed service record for a task.
@Model
final class MaintenanceLog {
    var uuid: UUID = UUID()
    var date: Date = Date()
    /// Meter reading (hours/miles) at time of service.
    var meterAtService: Double? = nil
    var cost: Decimal? = nil
    var performedBy: String = ""
    var notes: String = ""
    var task: MaintenanceTask? = nil

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceAttachment.log)
    var attachments: [MaintenanceAttachment]? = nil

    /// Parts/fluids consumed by this service (drives inventory decrement).
    @Relationship(deleteRule: .cascade, inverse: \ServicePartUsage.log)
    var partsUsed: [ServicePartUsage]? = nil

    init(
        date: Date = Date(),
        meterAtService: Double? = nil,
        cost: Decimal? = nil,
        performedBy: String = "",
        notes: String = "",
        task: MaintenanceTask? = nil
    ) {
        self.date = date
        self.meterAtService = meterAtService
        self.cost = cost
        self.performedBy = performedBy
        self.notes = notes
        self.task = task
    }

    var sortedPartsUsed: [ServicePartUsage] {
        (partsUsed ?? []).sorted { $0.displayName < $1.displayName }
    }

    /// "Oil filter ×1, Engine oil ×2.5" for rows and PDF reports.
    var partsUsedSummary: String {
        sortedPartsUsed
            .map { "\($0.displayName) ×\($0.quantity.formatted(.number.precision(.fractionLength(0...1))))" }
            .joined(separator: ", ")
    }
}

// MARK: - Attachment

enum AttachmentKind: String, CaseIterable, Identifiable {
    case photo = "Photo"
    case receipt = "Receipt"
    case pdf = "PDF"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .photo: return "photo.fill"
        case .receipt: return "receipt.fill"
        case .pdf: return "doc.fill"
        }
    }
}

/// A photo, receipt, or PDF attached either to a machine or to a service log.
@Model
final class MaintenanceAttachment {
    var uuid: UUID = UUID()
    var kindRaw: String = AttachmentKind.photo.rawValue
    var fileName: String = ""
    @Attribute(.externalStorage) var data: Data = Data()
    var createdAt: Date = Date()
    var equipment: Equipment? = nil
    var log: MaintenanceLog? = nil

    init(kind: AttachmentKind, fileName: String, data: Data) {
        self.kindRaw = kind.rawValue
        self.fileName = fileName
        self.data = data
    }

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRaw) ?? .photo }
        set { kindRaw = newValue.rawValue }
    }
}
