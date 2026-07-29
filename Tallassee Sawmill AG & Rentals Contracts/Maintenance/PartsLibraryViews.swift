//
//  PartsLibraryViews.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Master parts library: searchable list (by OEM number, cross refs,
//  description, supplier), part detail, and the add/edit form.
//

import SwiftUI
import SwiftData

// MARK: - Parts Library List

struct PartsLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Part.partDescription) private var parts: [Part]
    @State private var searchText = ""
    @State private var showingAddPart = false

    private var filteredParts: [Part] {
        parts.filter { $0.matches(searchText) }
    }

    var body: some View {
        List {
            ForEach(filteredParts, id: \.uuid) { part in
                NavigationLink {
                    PartDetailView(part: part)
                } label: {
                    PartRow(part: part)
                }
            }
            .onDelete { offsets in
                let items = filteredParts
                for index in offsets {
                    modelContext.delete(items[index])
                }
            }
        }
        .overlay {
            if filteredParts.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Parts",
                        systemImage: "shippingbox",
                        description: Text("Add parts to build your master library.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText, prompt: "OEM #, cross ref, description")
        .navigationTitle("Parts Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddPart = true
                } label: {
                    Label("Add Part", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPart) {
            NavigationStack {
                PartFormView(part: nil)
            }
        }
    }
}

// MARK: - Part Row

struct PartRow: View {
    let part: Part

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(part.partDescription.isEmpty ? "Untitled Part" : part.partDescription)
                    .font(.headline)
                HStack(spacing: 6) {
                    Image(systemName: part.kind.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if part.oemNumber.isEmpty {
                        Text("No OEM #")
                            .foregroundStyle(.orange)
                    } else {
                        Text(part.oemNumber)
                            .foregroundStyle(.secondary)
                    }
                    if let price = part.lastPrice {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            Spacer()
            // Stock on hand, highlighted when at or below the low-stock threshold.
            if part.isLowStock {
                Label(part.stockSummary, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            } else {
                Text(part.stockSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Part Detail

struct PartDetailView: View {
    @Bindable var part: Part
    @Environment(\.modelContext) private var modelContext

    @State private var showingEdit = false
    @State private var showingAddPurchase = false
    @State private var showingStockAdjust = false
    @State private var stockInput: Double?

    var body: some View {
        List {
            Section("Part") {
                LabeledContent("Type", value: part.kind.rawValue)
                LabeledContent("Description", value: part.partDescription)
                LabeledContent("OEM Number", value: part.oemNumber.isEmpty ? "—" : part.oemNumber)
                if !part.crossRefs.isEmpty {
                    LabeledContent("Cross Refs", value: part.crossRefs)
                }
            }

            inventorySection

            Section("Purchasing") {
                LabeledContent("Preferred Supplier",
                               value: part.preferredSupplier.isEmpty ? "—" : part.preferredSupplier)
                LabeledContent("Last Price") {
                    if let price = part.lastPrice {
                        Text(price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                    } else {
                        Text("—")
                    }
                }
                if let url = part.orderURL {
                    Link(destination: url) {
                        Label("Reorder Online", systemImage: "cart")
                    }
                }
            }

            purchaseHistorySection

            if !part.notes.isEmpty {
                Section("Notes") {
                    Text(part.notes)
                }
            }

            let links = (part.equipmentLinks ?? []).compactMap(\.equipment)
            if !links.isEmpty {
                Section("Used On") {
                    ForEach(links, id: \.uuid) { machine in
                        Label(machine.name, systemImage: machine.category.systemImage)
                    }
                }
            }
        }
        .navigationTitle(part.partDescription.isEmpty ? "Part" : part.partDescription)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                PartFormView(part: part)
            }
        }
        .sheet(isPresented: $showingAddPurchase) {
            NavigationStack {
                PartPurchaseFormView(part: part)
            }
        }
        .alert("Adjust Stock", isPresented: $showingStockAdjust) {
            TextField("On hand (\(part.unit))", value: $stockInput, format: .number)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let stockInput {
                    part.quantityOnHand = max(0, stockInput)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set the current quantity on hand (for corrections after a stock count).")
        }
    }

    private var inventorySection: some View {
        Section("Inventory") {
            LabeledContent("On Hand") {
                Button {
                    stockInput = part.quantityOnHand
                    showingStockAdjust = true
                } label: {
                    HStack(spacing: 4) {
                        Text(part.stockSummary)
                        Image(systemName: "pencil.circle")
                    }
                }
            }
            LabeledContent("Low Stock Warning",
                           value: part.lowStockThreshold > 0
                           ? "At \(part.lowStockThreshold.formatted(.number.precision(.fractionLength(0...1)))) \(part.unit)"
                           : "Off")
            if part.isLowStock {
                Label("Stock is low — reorder before the next service.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var purchaseHistorySection: some View {
        Section("Purchase History") {
            if part.sortedPurchases.isEmpty {
                Text("No purchases recorded yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(part.sortedPurchases, id: \.uuid) { purchase in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(purchase.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        if let unitPrice = purchase.unitPrice {
                            Text("\(purchase.quantity.formatted(.number.precision(.fractionLength(0...1)))) × \(unitPrice.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Qty \(purchase.quantity.formatted(.number.precision(.fractionLength(0...1))))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !purchase.supplier.isEmpty {
                        Text(purchase.supplier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deletePurchases)

            Button {
                showingAddPurchase = true
            } label: {
                Label("Record Purchase", systemImage: "plus")
            }
        }
    }

    /// Deleting a purchase record does not change stock — stock reflects the
    /// shelf, and old records may already be consumed.
    private func deletePurchases(at offsets: IndexSet) {
        let purchases = part.sortedPurchases
        for index in offsets {
            modelContext.delete(purchases[index])
        }
    }
}

// MARK: - Purchase Form

/// Records a purchase: adds to the price history, bumps stock on hand, and
/// updates the part's last price (and supplier if one wasn't set).
struct PartPurchaseFormView: View {
    @Bindable var part: Part

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var supplier = ""
    @State private var quantity: Double = 1
    @State private var unitPrice: Decimal?
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Purchase") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Supplier", text: $supplier)
                TextField("Quantity (\(part.unit))", value: $quantity, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Unit Price",
                          value: $unitPrice,
                          format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .keyboardType(.decimalPad)
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .navigationTitle("Record Purchase")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(quantity <= 0)
            }
        }
        .onAppear {
            supplier = part.preferredSupplier
        }
    }

    private func save() {
        let purchase = PartPurchase(
            date: date,
            supplier: supplier,
            quantity: quantity,
            unitPrice: unitPrice,
            notes: notes
        )
        purchase.part = part
        modelContext.insert(purchase)

        part.quantityOnHand += quantity
        if let unitPrice {
            part.lastPrice = unitPrice
        }
        if part.preferredSupplier.isEmpty {
            part.preferredSupplier = supplier
        }
        dismiss()
    }
}

// MARK: - Part Form (add / edit)

struct PartFormView: View {
    /// nil = creating a new part.
    let part: Part?
    /// Called with the saved part (used by "add part to machine" flows).
    var onSave: ((Part) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var kind: PartKind = .part
    @State private var oemNumber = ""
    @State private var partDescription = ""
    @State private var crossRefs = ""
    @State private var preferredSupplier = ""
    @State private var lastPrice: Decimal?
    @State private var orderLink = ""
    @State private var notes = ""
    @State private var unit = "ea"
    @State private var quantityOnHand: Double = 0
    @State private var lowStockThreshold: Double = 0

    var body: some View {
        Form {
            Section("Part") {
                Picker("Type", selection: $kind) {
                    ForEach(PartKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Description (e.g. Engine oil filter)", text: $partDescription)
                TextField("OEM Number", text: $oemNumber)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                TextField("Aftermarket Cross Refs (comma separated)", text: $crossRefs)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }

            Section {
                TextField("Unit (ea, qt, gal, tube, …)", text: $unit)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Quantity On Hand", value: $quantityOnHand, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Low Stock Warning At", value: $lowStockThreshold, format: .number)
                    .keyboardType(.decimalPad)
            } header: {
                Text("Inventory")
            } footer: {
                Text("You'll be warned when stock falls to the warning level. Set it to 0 to turn warnings off.")
            }

            Section("Purchasing") {
                TextField("Preferred Supplier", text: $preferredSupplier)
                TextField("Last Price",
                          value: $lastPrice,
                          format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .keyboardType(.decimalPad)
                TextField("Order Link (URL)", text: $orderLink)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(part == nil ? "New Part" : "Edit Part")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(partDescription.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let part else { return }
        kind = part.kind
        oemNumber = part.oemNumber
        partDescription = part.partDescription
        crossRefs = part.crossRefs
        preferredSupplier = part.preferredSupplier
        lastPrice = part.lastPrice
        orderLink = part.orderLink
        notes = part.notes
        unit = part.unit
        quantityOnHand = part.quantityOnHand
        lowStockThreshold = part.lowStockThreshold
    }

    private func save() {
        let saved: Part
        if let part {
            saved = part
        } else {
            saved = Part()
            modelContext.insert(saved)
        }
        saved.kind = kind
        saved.oemNumber = oemNumber.trimmingCharacters(in: .whitespaces)
        saved.partDescription = partDescription.trimmingCharacters(in: .whitespaces)
        saved.crossRefs = crossRefs
        saved.preferredSupplier = preferredSupplier
        saved.lastPrice = lastPrice
        saved.orderLink = orderLink.trimmingCharacters(in: .whitespaces)
        saved.notes = notes
        saved.unit = unit.trimmingCharacters(in: .whitespaces).isEmpty ? "ea" : unit.trimmingCharacters(in: .whitespaces)
        saved.quantityOnHand = max(0, quantityOnHand)
        saved.lowStockThreshold = max(0, lowStockThreshold)
        onSave?(saved)
        dismiss()
    }
}

// MARK: - Add Part to Machine

/// Sheet that links a part from the master library to a machine, or creates a
/// brand-new part and links it in one step.
struct AddPartToEquipmentView: View {
    let equipment: Equipment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Part.partDescription) private var parts: [Part]
    @State private var searchText = ""
    @State private var showingNewPart = false

    /// Parts not already linked to this machine, filtered by search.
    private var availableParts: [Part] {
        let linkedIDs = Set((equipment.partLinks ?? []).compactMap { $0.part?.uuid })
        return parts.filter { !linkedIDs.contains($0.uuid) && $0.matches(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingNewPart = true
                    } label: {
                        Label("Create New Part", systemImage: "plus.circle.fill")
                    }
                }

                Section("From Parts Library") {
                    if availableParts.isEmpty {
                        Text(searchText.isEmpty ? "All library parts are already linked." : "No matches.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(availableParts, id: \.uuid) { part in
                        Button {
                            link(part)
                        } label: {
                            PartRow(part: part)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "OEM #, cross ref, description")
            .navigationTitle("Add Part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingNewPart) {
                NavigationStack {
                    PartFormView(part: nil) { newPart in
                        link(newPart)
                    }
                }
            }
        }
    }

    private func link(_ part: Part) {
        let link = EquipmentPart(equipment: equipment, part: part)
        modelContext.insert(link)
        dismiss()
    }
}
