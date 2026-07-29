//
//  ServiceKitViews.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Kits & service packages: named bundles of parts/fluids (e.g. "250-hr
//  service") with stock readiness, editable line quantities, and a part
//  picker backed by the master library.
//

import SwiftUI
import SwiftData

// MARK: - Kits List

struct ServiceKitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ServiceKit.name) private var kits: [ServiceKit]
    @State private var showingAdd = false

    var body: some View {
        List {
            ForEach(kits, id: \.uuid) { kit in
                NavigationLink {
                    ServiceKitDetailView(kit: kit)
                } label: {
                    ServiceKitRow(kit: kit)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    modelContext.delete(kits[index])
                }
            }
        }
        .overlay {
            if kits.isEmpty {
                ContentUnavailableView(
                    "No Kits",
                    systemImage: "shippingbox.and.arrow.backward",
                    description: Text("Bundle the parts and fluids for a job — like a 250-hour service — so you can apply them in one tap.")
                )
            }
        }
        .navigationTitle("Kits & Packages")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Kit", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                ServiceKitFormView(kit: nil)
            }
        }
    }
}

struct ServiceKitRow: View {
    let kit: ServiceKit

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kit.name)
                    .font(.headline)
                Text("\((kit.items ?? []).count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            readinessBadge
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var readinessBadge: some View {
        if (kit.items ?? []).isEmpty {
            Text("Empty")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        } else if kit.isReady {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)
        } else {
            Label("Missing \(kit.shortItems.count)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Kit Detail

struct ServiceKitDetailView: View {
    @Bindable var kit: ServiceKit
    @Environment(\.modelContext) private var modelContext

    @State private var showingEdit = false
    @State private var showingAddPart = false

    var body: some View {
        List {
            readinessSection
            itemsSection

            if !kit.notes.isEmpty {
                Section("Notes") {
                    Text(kit.notes)
                }
            }

            let taskNames = (kit.tasks ?? []).compactMap { task -> String? in
                guard let machine = task.equipment?.name else { return task.name }
                return "\(machine): \(task.name)"
            }
            if !taskNames.isEmpty {
                Section("Default Kit For") {
                    ForEach(taskNames.sorted(), id: \.self) { name in
                        Label(name, systemImage: "checklist")
                    }
                }
            }
        }
        .navigationTitle(kit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                ServiceKitFormView(kit: kit)
            }
        }
        .sheet(isPresented: $showingAddPart) {
            KitPartPickerView(kit: kit)
        }
    }

    private var readinessSection: some View {
        Section {
            if (kit.items ?? []).isEmpty {
                Text("Add parts to this kit to track readiness.")
                    .foregroundStyle(.secondary)
            } else if kit.isReady {
                Label("All items in stock — kit is ready to go.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("\(kit.shortItems.count) item(s) short — reorder before this job.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var itemsSection: some View {
        Section("Parts & Fluids") {
            ForEach(kit.sortedItems, id: \.uuid) { item in
                KitItemRow(item: item)
            }
            .onDelete { offsets in
                let items = kit.sortedItems
                for index in offsets {
                    modelContext.delete(items[index])
                }
            }
            Button {
                showingAddPart = true
            } label: {
                Label("Add Part", systemImage: "plus")
            }
        }
    }
}

/// One kit line with an editable quantity and a stock check.
private struct KitItemRow: View {
    @Bindable var item: ServiceKitItem

    private var isShort: Bool {
        guard let part = item.part else { return true }
        return part.quantityOnHand < item.quantity
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                if let part = item.part {
                    Text("On hand: \(part.stockSummary)")
                        .font(.caption)
                        .foregroundStyle(isShort ? .red : .secondary)
                } else {
                    Text("Part no longer in library")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Stepper(
                value: $item.quantity,
                in: 0.5...999, step: 1
            ) {
                Text("×\(item.quantity.formatted(.number.precision(.fractionLength(0...1))))")
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }
}

// MARK: - Kit Form (name / notes)

struct ServiceKitFormView: View {
    /// nil = creating a new kit.
    let kit: ServiceKit?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Kit") {
                TextField("Name (e.g. SVL75 250-hr service)", text: $name)
            }
            Section("Notes") {
                TextField("Notes (procedure, torque specs, …)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(kit == nil ? "New Kit" : "Edit Kit")
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
        .onAppear {
            guard let kit else { return }
            name = kit.name
            notes = kit.notes
        }
    }

    private func save() {
        let saved: ServiceKit
        if let kit {
            saved = kit
        } else {
            saved = ServiceKit()
            modelContext.insert(saved)
        }
        saved.name = name.trimmingCharacters(in: .whitespaces)
        saved.notes = notes
        dismiss()
    }
}

// MARK: - Kit Part Picker

/// Adds a part from the master library to a kit.
struct KitPartPickerView: View {
    let kit: ServiceKit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Part.partDescription) private var parts: [Part]
    @State private var searchText = ""

    private var availableParts: [Part] {
        let inKit = Set((kit.items ?? []).compactMap { $0.part?.uuid })
        return parts.filter { !inKit.contains($0.uuid) && $0.matches(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableParts.isEmpty {
                    Text(searchText.isEmpty ? "Every library part is already in this kit." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(availableParts, id: \.uuid) { part in
                    Button {
                        let item = ServiceKitItem(quantity: 1, part: part, kit: kit)
                        modelContext.insert(item)
                        dismiss()
                    } label: {
                        PartRow(part: part)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "OEM #, cross ref, description")
            .navigationTitle("Add to Kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
