//
//  MaintenanceStore.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  SwiftData container setup and one-time seed data for the maintenance module.
//

import Foundation
import SwiftData

@MainActor
enum MaintenanceStore {

    /// Shared container for the whole app. Attached to the window group in
    /// Tallassee_Sawmill_AG___Rentals_ContractsApp.
    static let container: ModelContainer = {
        let schema = Schema([
            Equipment.self,
            EquipmentPhoto.self,
            Part.self,
            PartPurchase.self,
            ServicePartUsage.self,
            EquipmentPart.self,
            MaintenanceTask.self,
            MaintenanceLog.self,
            MaintenanceAttachment.self,
        ])

        // To turn on CloudKit sync later:
        //   1. In Signing & Capabilities, add iCloud → CloudKit and create a container.
        //   2. Add the Background Modes → Remote notifications capability.
        //   3. Change `cloudKitDatabase: .none` below to
        //      `cloudKitDatabase: .private("iCloud.<your-container-id>")`.
        // The models are already CloudKit-compatible (defaults everywhere,
        // optional relationships, no unique constraints).
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            seedIfNeeded(context: container.mainContext)
            return container
        } catch {
            fatalError("Failed to create maintenance ModelContainer: \(error)")
        }
    }()

    // MARK: - Seeding

    /// Preloads the two Kubota machines and their parts the first time the
    /// store is created. Skipped whenever any equipment already exists.
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Equipment>())) ?? 0
        guard existing == 0 else { return }

        seedSVL75(context: context)
        seedKX033(context: context)
        try? context.save()
    }

    private static func seedSVL75(context: ModelContext) {
        let svl = Equipment(
            name: "Kubota SVL75-3",
            category: .trackLoader,
            make: "Kubota",
            model: "SVL75-3",
            meterType: .hours
        )
        context.insert(svl)

        addPart(oem: "V0531-43150", description: "Engine air filter — outer element",
                usage: "Engine intake — outer", to: svl, context: context)
        addPart(oem: "V0531-43140", description: "Engine air filter — inner element",
                usage: "Engine intake — inner (safety)", to: svl, context: context)
        addPart(oem: "V1311-39850", description: "Cab air filter — outer",
                usage: "Cab HVAC — outer", to: svl, context: context)
        addPart(oem: "V1311-39810", description: "Cab air filter — inner",
                usage: "Cab HVAC — inner (recirculation)", to: svl, context: context)

        // Placeholder rows — fill in OEM numbers when known.
        addPlaceholder(description: "Engine oil filter", to: svl, context: context)
        addPlaceholder(description: "Fuel filter", to: svl, context: context)
        addPlaceholder(description: "Hydraulic oil filter", to: svl, context: context)
        addPlaceholder(description: "Drive belts", to: svl, context: context)
        addPlaceholder(description: "Battery", to: svl, context: context)
    }

    private static func seedKX033(context: ModelContext) {
        let kx = Equipment(
            name: "Kubota KX033-4",
            category: .excavator,
            make: "Kubota",
            model: "KX033-4",
            meterType: .hours
        )
        context.insert(kx)

        // OEM filter rows — verify part numbers against the operator's manual
        // or dealer before ordering, then fill in the OEM field.
        addPlaceholder(description: "Engine oil filter (OEM)", to: kx, context: context)
        addPlaceholder(description: "Fuel filter (OEM)", to: kx, context: context)
        addPlaceholder(description: "Hydraulic return filter (OEM)", to: kx, context: context)

        // Consumable / wear-item placeholders.
        addPlaceholder(description: "Engine air filter — outer", to: kx, context: context)
        addPlaceholder(description: "Engine air filter — inner", to: kx, context: context)
        addPlaceholder(description: "Grease — general purpose", kind: .fluid, unit: "tube", to: kx, context: context)
        addPlaceholder(description: "Engine oil", kind: .fluid, unit: "qt", to: kx, context: context)
        addPlaceholder(description: "Hydraulic oil", kind: .fluid, unit: "gal", to: kx, context: context)
        addPlaceholder(description: "Coolant", kind: .fluid, unit: "gal", to: kx, context: context)
        addPlaceholder(description: "Battery", to: kx, context: context)
        addPlaceholder(description: "Belts", to: kx, context: context)
    }

    /// Creates a master-library part and links it to a machine.
    @discardableResult
    private static func addPart(
        oem: String,
        description: String,
        kind: PartKind = .part,
        unit: String = "ea",
        notes: String = "",
        usage: String = "",
        to equipment: Equipment,
        context: ModelContext
    ) -> Part {
        let part = Part(kind: kind, oemNumber: oem, partDescription: description, notes: notes, unit: unit)
        context.insert(part)
        let link = EquipmentPart(usageNote: usage, equipment: equipment, part: part)
        context.insert(link)
        return part
    }

    private static func addPlaceholder(
        description: String,
        kind: PartKind = .part,
        unit: String = "ea",
        to equipment: Equipment,
        context: ModelContext
    ) {
        addPart(
            oem: "",
            description: description,
            kind: kind,
            unit: unit,
            notes: "Placeholder — add OEM number.",
            to: equipment,
            context: context
        )
    }
}
