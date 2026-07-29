//
//  MaintenanceTaskViews.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Maintenance items: color-coded rows, detail with service history,
//  the add/edit schedule form, and the "complete service" sheet.
//

import SwiftUI
import SwiftData

// MARK: - Task Row

/// Color-coded row used on the dashboard and on equipment detail screens.
struct MaintenanceTaskRow: View {
    let task: MaintenanceTask
    /// Show the machine name (used on the dashboard where rows mix machines).
    var showsEquipment = false

    var body: some View {
        let status = task.status()
        HStack(spacing: 12) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.headline)
                if showsEquipment {
                    Text(task.equipment?.name ?? "Unassigned")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(task.dueSummary)
                    .font(.caption)
                    .foregroundStyle(status == .upToDate ? Color.secondary : status.color)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Task Detail

struct MaintenanceTaskDetailView: View {
    @Bindable var task: MaintenanceTask
    @Environment(\.modelContext) private var modelContext

    @State private var showingEdit = false
    @State private var showingComplete = false

    var body: some View {
        List {
            statusSection
            scheduleSection

            if !task.notes.isEmpty {
                Section("Notes") {
                    Text(task.notes)
                }
            }

            Section("Service History") {
                if task.sortedLogs.isEmpty {
                    Text("No services recorded yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(task.sortedLogs, id: \.uuid) { log in
                    NavigationLink {
                        MaintenanceLogDetailView(log: log)
                    } label: {
                        MaintenanceLogRow(log: log)
                    }
                }
                .onDelete(perform: deleteLogs)
            }
        }
        .navigationTitle(task.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                MaintenanceTaskFormView(equipment: task.equipment, task: task)
            }
        }
        .sheet(isPresented: $showingComplete) {
            NavigationStack {
                CompleteServiceView(task: task)
            }
        }
    }

    private var statusSection: some View {
        let status = task.status()
        return Section {
            HStack {
                Label(status.label, systemImage: status.systemImage)
                    .font(.headline)
                    .foregroundStyle(status.color)
                Spacer()
                Button {
                    showingComplete = true
                } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            Text(task.dueSummary)
                .foregroundStyle(.secondary)
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            if let intervalMeter = task.intervalMeter {
                let unit = task.equipment?.meterType.unitAbbreviation ?? "hrs"
                LabeledContent("Interval",
                               value: "Every \(intervalMeter.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
            }
            if let intervalDays = task.intervalDays {
                LabeledContent("Calendar Interval", value: "Every \(intervalDays) days")
            }
            if let lastDate = task.lastDoneDate {
                LabeledContent("Last Done", value: lastDate.formatted(date: .abbreviated, time: .omitted))
            }
            if let lastMeter = task.lastDoneMeter {
                let unit = task.equipment?.meterType.unitAbbreviation ?? "hrs"
                LabeledContent("Last Done At",
                               value: "\(lastMeter.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
            }
            LabeledContent("Reminder",
                           value: task.reminderEnabled ? "\(task.reminderLeadDays) days before due" : "Off")
        }
    }

    private func deleteLogs(at offsets: IndexSet) {
        let logs = task.sortedLogs
        for index in offsets {
            modelContext.delete(logs[index])
        }
    }
}

// MARK: - Task Form (add / edit)

struct MaintenanceTaskFormView: View {
    /// The machine the task belongs to (required for new tasks).
    let equipment: Equipment?
    /// nil = creating a new task.
    let task: MaintenanceTask?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var intervalMeter: Double?
    @State private var intervalDays: Int?
    @State private var hasBaseline = false
    @State private var lastDoneDate = Date()
    @State private var lastDoneMeter: Double?
    @State private var reminderEnabled = false
    @State private var reminderLeadDays = 7
    @State private var notes = ""
    @State private var defaultKit: ServiceKit?
    @Query(sort: \ServiceKit.name) private var kits: [ServiceKit]

    private var meterUnit: String {
        equipment?.meterType.unitAbbreviation ?? "hrs"
    }

    var body: some View {
        Form {
            Section("Maintenance Item") {
                TextField("Name (e.g. Engine oil & filter)", text: $name)
            }

            Section {
                TextField("Interval (\(meterUnit))", value: $intervalMeter, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Interval (days)", value: $intervalDays, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
            } header: {
                Text("Intervals")
            } footer: {
                Text("Set either or both. Whichever comes due first wins.")
            }

            Section("Last Done") {
                Toggle("Serviced Before", isOn: $hasBaseline)
                if hasBaseline {
                    DatePicker("Date", selection: $lastDoneDate, displayedComponents: .date)
                    TextField("Meter reading (\(meterUnit))", value: $lastDoneMeter, format: .number)
                        .keyboardType(.decimalPad)
                }
            }

            if !kits.isEmpty {
                Section {
                    Picker("Default Kit", selection: $defaultKit) {
                        Text("None").tag(ServiceKit?.none)
                        ForEach(kits, id: \.uuid) { kit in
                            Text(kit.name).tag(ServiceKit?.some(kit))
                        }
                    }
                } footer: {
                    Text("The kit's parts and quantities prefill the Complete Service sheet.")
                }
            }

            Section {
                Toggle("Reminder Notification", isOn: $reminderEnabled)
                if reminderEnabled {
                    Stepper("Notify \(reminderLeadDays) days before due",
                            value: $reminderLeadDays, in: 0...60)
                }
            } footer: {
                Text("Reminders fire for calendar-based due dates. Hour-based items show on the dashboard as the meter climbs.")
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(task == nil ? "New Maintenance Item" : "Edit Maintenance Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let task else { return }
        name = task.name
        intervalMeter = task.intervalMeter
        intervalDays = task.intervalDays
        hasBaseline = task.lastDoneDate != nil || task.lastDoneMeter != nil
        lastDoneDate = task.lastDoneDate ?? Date()
        lastDoneMeter = task.lastDoneMeter
        reminderEnabled = task.reminderEnabled
        reminderLeadDays = task.reminderLeadDays
        notes = task.notes
        defaultKit = task.defaultKit
    }

    private func save() {
        let saved: MaintenanceTask
        if let task {
            saved = task
        } else {
            saved = MaintenanceTask(equipment: equipment)
            modelContext.insert(saved)
        }
        saved.name = name.trimmingCharacters(in: .whitespaces)
        saved.intervalMeter = intervalMeter
        saved.intervalDays = intervalDays
        saved.lastDoneDate = hasBaseline ? lastDoneDate : nil
        saved.lastDoneMeter = hasBaseline ? lastDoneMeter : nil
        saved.reminderEnabled = reminderEnabled
        saved.reminderLeadDays = reminderLeadDays
        saved.notes = notes
        saved.defaultKit = defaultKit

        if reminderEnabled {
            Task {
                _ = await ReminderScheduler.requestAuthorization()
                ReminderScheduler.sync(task: saved)
            }
        } else {
            ReminderScheduler.sync(task: saved)
        }
        Task { await JobCalendarSync.syncMaintenance(saved) }
        dismiss()
    }
}

// MARK: - Complete Service

/// Records a service: creates a log, moves the task's baseline forward, and
/// optionally updates the machine's current meter reading.
struct CompleteServiceView: View {
    @Bindable var task: MaintenanceTask

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var meterAtService: Double?
    @State private var updateEquipmentMeter = true
    @State private var cost: Decimal?
    @State private var performedBy = ""
    @State private var notes = ""
    /// Quantity of each machine part consumed by this service, keyed by part UUID.
    @State private var usedQuantities: [UUID: Double] = [:]
    @State private var lowStockMessage: String?
    /// Kit parts that aren't linked to this machine but were pulled in by a kit.
    @State private var extraParts: [Part] = []
    @Query(sort: \ServiceKit.name) private var kits: [ServiceKit]

    private var meterUnit: String {
        task.equipment?.meterType.unitAbbreviation ?? "hrs"
    }

    /// Parts linked to this machine, offered for consumption.
    private var machineParts: [Part] {
        (task.equipment?.sortedPartLinks ?? []).compactMap(\.part)
    }

    /// Machine parts plus anything a kit added, without duplicates.
    private var selectableParts: [Part] {
        var seen = Set(machineParts.map(\.uuid))
        var all = machineParts
        for part in extraParts where !seen.contains(part.uuid) {
            seen.insert(part.uuid)
            all.append(part)
        }
        return all
    }

    var body: some View {
        Form {
            Section("Service") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Meter reading (\(meterUnit))", value: $meterAtService, format: .number)
                    .keyboardType(.decimalPad)
                if meterAtService != nil {
                    Toggle("Update machine's current \(meterUnit)", isOn: $updateEquipmentMeter)
                }
            }

            if !selectableParts.isEmpty || !kits.isEmpty {
                partsUsedSection
            }

            Section("Details") {
                TextField("Cost",
                          value: $cost,
                          format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .keyboardType(.decimalPad)
                TextField("Performed By", text: $performedBy)
                TextField("Notes (torque specs, observations, …)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Complete Service")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            meterAtService = task.equipment.map { $0.currentMeter }
            // Prefill from the task's default kit, if one is set.
            if let kit = task.defaultKit {
                apply(kit)
            }
        }
        // Shown after saving when the service dropped any stock to a low level.
        .alert("Low Stock", isPresented: .init(
            get: { lowStockMessage != nil },
            set: { if !$0 { lowStockMessage = nil; dismiss() } }
        )) {
            Button("OK") {
                lowStockMessage = nil
                dismiss()
            }
        } message: {
            Text(lowStockMessage ?? "")
        }
    }

    /// One row per part with a quantity stepper; whatever is entered here is
    /// decremented from inventory on save. A kit can fill the quantities in
    /// one tap.
    private var partsUsedSection: some View {
        Section {
            if !kits.isEmpty {
                Menu {
                    ForEach(kits, id: \.uuid) { kit in
                        Button {
                            apply(kit)
                        } label: {
                            if kit.isReady {
                                Label(kit.name, systemImage: "checkmark.circle")
                            } else {
                                Label("\(kit.name) (short \(kit.shortItems.count))",
                                      systemImage: "exclamationmark.triangle")
                            }
                        }
                    }
                } label: {
                    Label("Apply Kit", systemImage: "shippingbox.and.arrow.backward")
                }
            }

            ForEach(selectableParts, id: \.uuid) { part in
                let quantity = usedQuantities[part.uuid] ?? 0
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.partDescription)
                        if quantity > part.quantityOnHand {
                            Text("Only \(part.stockSummary) on hand")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("On hand: \(part.stockSummary)")
                                .font(.caption)
                                .foregroundStyle(part.isLowStock ? .red : .secondary)
                        }
                    }
                    Spacer()
                    Stepper(
                        value: .init(
                            get: { usedQuantities[part.uuid] ?? 0 },
                            set: { usedQuantities[part.uuid] = max(0, $0) }
                        ),
                        in: 0...999, step: 1
                    ) {
                        Text(quantity.formatted(.number.precision(.fractionLength(0...1))))
                            .monospacedDigit()
                            .foregroundStyle(quantity > 0 ? .primary : .secondary)
                    }
                }
            }
        } header: {
            Text("Parts & Fluids Used")
        } footer: {
            Text("Used quantities are subtracted from inventory automatically.")
        }
    }

    /// Sets each kit line's quantity, pulling in parts not linked to the machine.
    private func apply(_ kit: ServiceKit) {
        for item in kit.sortedItems {
            guard let part = item.part else { continue }
            usedQuantities[part.uuid] = item.quantity
            if !machineParts.contains(where: { $0.uuid == part.uuid }),
               !extraParts.contains(where: { $0.uuid == part.uuid }) {
                extraParts.append(part)
            }
        }
    }

    private func save() {
        let log = MaintenanceLog(
            date: date,
            meterAtService: meterAtService,
            cost: cost,
            performedBy: performedBy,
            notes: notes,
            task: task
        )
        modelContext.insert(log)

        // Record consumed parts and decrement inventory.
        var nowLow: [Part] = []
        for part in selectableParts {
            guard let quantity = usedQuantities[part.uuid], quantity > 0 else { continue }
            let usage = ServicePartUsage(quantity: quantity, part: part, log: log)
            modelContext.insert(usage)

            let wasLow = part.isLowStock
            part.quantityOnHand = max(0, part.quantityOnHand - quantity)
            // Warn on newly-low items, and on anything that just hit zero.
            if (part.isLowStock && !wasLow) || part.quantityOnHand == 0 {
                nowLow.append(part)
            }
        }

        // Move the schedule baseline forward.
        task.lastDoneDate = date
        if let meterAtService {
            task.lastDoneMeter = meterAtService
            if updateEquipmentMeter, let equipment = task.equipment,
               meterAtService > equipment.currentMeter {
                equipment.currentMeter = meterAtService
            }
        }
        ReminderScheduler.sync(task: task)
        Task { await JobCalendarSync.syncMaintenance(task) }

        if nowLow.isEmpty {
            dismiss()
        } else {
            let lines = nowLow.map { "• \($0.partDescription): \($0.stockSummary) left" }
            lowStockMessage = "Reorder before the next job:\n\n" + lines.joined(separator: "\n")
        }
    }
}

// MARK: - Log Row & Detail

struct MaintenanceLogRow: View {
    let log: MaintenanceLog
    /// Show which task/machine this was for (used on the dashboard).
    var showsContext = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsContext {
                Text("\(log.task?.equipment?.name ?? "Equipment"): \(log.task?.name ?? "Service")")
                    .font(.headline)
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(log.date.formatted(date: .abbreviated, time: .omitted))
                if let meter = log.meterAtService {
                    let unit = log.task?.equipment?.meterType.unitAbbreviation ?? "hrs"
                    Text("· \(meter.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                        .foregroundStyle(.secondary)
                }
                if let cost = log.cost {
                    Text("· \(cost.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(showsContext ? .subheadline : .body)
        }
        .padding(.vertical, 2)
    }
}

struct MaintenanceLogDetailView: View {
    @Bindable var log: MaintenanceLog

    var body: some View {
        List {
            Section("Service") {
                LabeledContent("Task", value: log.task?.name ?? "—")
                LabeledContent("Machine", value: log.task?.equipment?.name ?? "—")
                LabeledContent("Date", value: log.date.formatted(date: .long, time: .omitted))
                if let meter = log.meterAtService {
                    let unit = log.task?.equipment?.meterType.unitAbbreviation ?? "hrs"
                    LabeledContent("Meter", value: "\(meter.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                }
                if let cost = log.cost {
                    LabeledContent("Cost",
                                   value: cost.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                }
                if !log.performedBy.isEmpty {
                    LabeledContent("Performed By", value: log.performedBy)
                }
            }

            if !log.sortedPartsUsed.isEmpty {
                Section("Parts & Fluids Used") {
                    ForEach(log.sortedPartsUsed, id: \.uuid) { usage in
                        HStack {
                            Text(usage.displayName)
                            Spacer()
                            Text("×\(usage.quantity.formatted(.number.precision(.fractionLength(0...1))))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !log.notes.isEmpty {
                Section("Notes") {
                    Text(log.notes)
                }
            }

            // Receipts, photos, and PDFs for this service.
            AttachmentSection(log: log)
        }
        .navigationTitle("Service Record")
        .navigationBarTitleDisplayMode(.inline)
    }
}
