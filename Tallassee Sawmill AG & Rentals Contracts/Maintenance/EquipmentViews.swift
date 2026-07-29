//
//  EquipmentViews.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Fleet screens: equipment list with category filter, machine detail
//  (photos, specs, maintenance items, parts, attachments), and the
//  add/edit form with a multi-photo picker.
//

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Equipment List

struct EquipmentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @State private var categoryFilter: EquipmentCategory?
    @State private var showingAdd = false

    private var filtered: [Equipment] {
        guard let categoryFilter else { return equipment }
        return equipment.filter { $0.category == categoryFilter }
    }

    var body: some View {
        List {
            ForEach(filtered, id: \.uuid) { machine in
                NavigationLink {
                    EquipmentDetailView(equipment: machine)
                } label: {
                    EquipmentRow(equipment: machine)
                }
            }
            .onDelete(perform: deleteEquipment)
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Equipment",
                    systemImage: "wrench.and.screwdriver",
                    description: Text(categoryFilter == nil
                                      ? "Add your first machine to start tracking maintenance."
                                      : "No machines in this category.")
                )
            }
        }
        .navigationTitle("Equipment")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: $categoryFilter) {
                        Text("All Categories").tag(EquipmentCategory?.none)
                        ForEach(EquipmentCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(EquipmentCategory?.some(category))
                        }
                    }
                } label: {
                    Label("Filter",
                          systemImage: categoryFilter == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Equipment", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                EquipmentFormView(equipment: nil)
            }
        }
    }

    private func deleteEquipment(at offsets: IndexSet) {
        let items = filtered
        for index in offsets {
            // Cancel any pending reminders before the cascade delete.
            for task in items[index].tasks ?? [] {
                ReminderScheduler.cancel(taskUUID: task.uuid)
            }
            modelContext.delete(items[index])
        }
    }
}

// MARK: - Equipment Row

struct EquipmentRow: View {
    let equipment: Equipment

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(equipment.name)
                    .font(.headline)
                Text("\(equipment.category.rawValue) · \(equipment.meterSummary)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Worst maintenance status at a glance.
            let status = equipment.worstStatus
            if status != .notScheduled {
                Circle()
                    .fill(status.color)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = equipment.primaryPhotoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: equipment.category.systemImage)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

// MARK: - Equipment Detail

struct EquipmentDetailView: View {
    @Bindable var equipment: Equipment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingAddTask = false
    @State private var showingAddPart = false
    @State private var showingMeterUpdate = false
    @State private var meterInput: Double?
    @State private var showingDeleteConfirmation = false
    @State private var historyReportURL: URL?

    var body: some View {
        List {
            if !equipment.sortedPhotos.isEmpty {
                photoSection
            }
            detailsSection
            maintenanceSection
            partsSection
            AttachmentSection(equipment: equipment)

            if !equipment.notes.isEmpty {
                Section("Notes") {
                    Text(equipment.notes)
                }
            }
        }
        .navigationTitle(equipment.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        historyReportURL = MaintenanceReports.machineHistory(equipment)
                    } label: {
                        Label("Export History PDF", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Equipment", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                EquipmentFormView(equipment: equipment)
            }
        }
        .sheet(isPresented: .init(
            get: { historyReportURL != nil },
            set: { if !$0 { historyReportURL = nil } }
        )) {
            if let historyReportURL {
                PDFPreviewSheet(url: historyReportURL, title: "Maintenance History")
            }
        }
        .sheet(isPresented: $showingAddTask) {
            NavigationStack {
                MaintenanceTaskFormView(equipment: equipment, task: nil)
            }
        }
        .sheet(isPresented: $showingAddPart) {
            AddPartToEquipmentView(equipment: equipment)
        }
        .alert("Update \(equipment.meterType.rawValue)", isPresented: $showingMeterUpdate) {
            TextField("Current reading", value: $meterInput, format: .number)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let meterInput {
                    equipment.currentMeter = meterInput
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the machine's current \(equipment.meterType.rawValue.lowercased()).")
        }
        .confirmationDialog(
            "Delete \(equipment.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                for task in equipment.tasks ?? [] {
                    ReminderScheduler.cancel(taskUUID: task.uuid)
                }
                modelContext.delete(equipment)
                dismiss()
            }
        } message: {
            Text("This removes the machine, its maintenance history, photos, and attachments. Parts stay in the library.")
        }
    }

    // Swipeable photo gallery.
    private var photoSection: some View {
        Section {
            TabView {
                ForEach(equipment.sortedPhotos, id: \.uuid) { photo in
                    if let image = UIImage(data: photo.imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
            .tabViewStyle(.page)
            .frame(height: 220)
            .listRowInsets(EdgeInsets())
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Category", value: equipment.category.rawValue)
            if !equipment.make.isEmpty {
                LabeledContent("Make", value: equipment.make)
            }
            if !equipment.model.isEmpty {
                LabeledContent("Model", value: equipment.model)
            }
            if let year = equipment.year {
                LabeledContent("Year", value: String(year))
            }
            if !equipment.serialOrVIN.isEmpty {
                LabeledContent("Serial / VIN", value: equipment.serialOrVIN)
            }
            if let purchaseDate = equipment.purchaseDate {
                LabeledContent("Purchased", value: purchaseDate.formatted(date: .abbreviated, time: .omitted))
            }
            if let price = equipment.purchasePrice {
                LabeledContent("Purchase Price",
                               value: price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
            }
            LabeledContent(equipment.meterType.rawValue) {
                Button {
                    meterInput = equipment.currentMeter
                    showingMeterUpdate = true
                } label: {
                    HStack(spacing: 4) {
                        Text(equipment.meterSummary)
                        Image(systemName: "pencil.circle")
                    }
                }
            }
        }
    }

    private var maintenanceSection: some View {
        Section("Maintenance Items") {
            if equipment.sortedTasks.isEmpty {
                Text("No maintenance items yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(equipment.sortedTasks, id: \.uuid) { task in
                NavigationLink {
                    MaintenanceTaskDetailView(task: task)
                } label: {
                    MaintenanceTaskRow(task: task)
                }
            }
            .onDelete(perform: deleteTasks)

            Button {
                showingAddTask = true
            } label: {
                Label("Add Maintenance Item", systemImage: "plus")
            }
        }
    }

    private var partsSection: some View {
        Section("Parts") {
            if equipment.sortedPartLinks.isEmpty {
                Text("No parts linked yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(equipment.sortedPartLinks, id: \.uuid) { link in
                if let part = link.part {
                    NavigationLink {
                        PartDetailView(part: part)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            PartRow(part: part)
                            if !link.usageNote.isEmpty {
                                Text(link.usageNote)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onDelete(perform: unlinkParts)

            Button {
                showingAddPart = true
            } label: {
                Label("Add Part", systemImage: "plus")
            }
        }
    }

    private func deleteTasks(at offsets: IndexSet) {
        let tasks = equipment.sortedTasks
        for index in offsets {
            ReminderScheduler.cancel(taskUUID: tasks[index].uuid)
            modelContext.delete(tasks[index])
        }
    }

    /// Removes the link only — the part remains in the master library.
    private func unlinkParts(at offsets: IndexSet) {
        let links = equipment.sortedPartLinks
        for index in offsets {
            modelContext.delete(links[index])
        }
    }
}

// MARK: - Equipment Form (add / edit)

struct EquipmentFormView: View {
    /// nil = creating a new machine.
    let equipment: Equipment?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: EquipmentCategory = .other
    @State private var make = ""
    @State private var model = ""
    @State private var year: Int?
    @State private var serialOrVIN = ""
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var purchasePrice: Decimal?
    @State private var meterType: MeterType = .hours
    @State private var currentMeter: Double = 0
    @State private var notes = ""

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    /// Newly picked photos, kept in memory until Save.
    @State private var pendingPhotoData: [Data] = []

    var body: some View {
        Form {
            Section("Machine") {
                TextField("Name (e.g. Kubota SVL75-3)", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(EquipmentCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                TextField("Make", text: $make)
                TextField("Model", text: $model)
                TextField("Year", value: $year, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                TextField("Serial # / VIN", text: $serialOrVIN)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }

            Section("Purchase") {
                Toggle("Purchase Date", isOn: $hasPurchaseDate)
                if hasPurchaseDate {
                    DatePicker("Date", selection: $purchaseDate, displayedComponents: .date)
                }
                TextField("Purchase Price",
                          value: $purchasePrice,
                          format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .keyboardType(.decimalPad)
            }

            Section("Usage") {
                Picker("Tracked By", selection: $meterType) {
                    ForEach(MeterType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Current \(meterType.rawValue)", value: $currentMeter, format: .number)
                    .keyboardType(.decimalPad)
            }

            Section("Photos") {
                PhotosPicker(selection: $selectedPhotoItems,
                             maxSelectionCount: 10,
                             matching: .images) {
                    Label("Add Photos", systemImage: "photo.badge.plus")
                }
                if !pendingPhotoData.isEmpty {
                    pendingPhotoStrip
                }
                if let equipment, !equipment.sortedPhotos.isEmpty {
                    existingPhotoList(equipment)
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(equipment == nil ? "New Equipment" : "Edit Equipment")
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
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await loadPickedPhotos(newItems) }
        }
    }

    /// Horizontally scrolling previews of photos picked but not yet saved.
    private var pendingPhotoStrip: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(Array(pendingPhotoData.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    pendingPhotoData.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(2)
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func existingPhotoList(_ equipment: Equipment) -> some View {
        ForEach(equipment.sortedPhotos, id: \.uuid) { photo in
            HStack {
                if let image = UIImage(data: photo.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(photo.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
        }
        .onDelete { offsets in
            let photos = equipment.sortedPhotos
            for index in offsets {
                modelContext.delete(photos[index])
            }
        }
    }

    private func loadExisting() {
        guard let equipment else { return }
        name = equipment.name
        category = equipment.category
        make = equipment.make
        model = equipment.model
        year = equipment.year
        serialOrVIN = equipment.serialOrVIN
        hasPurchaseDate = equipment.purchaseDate != nil
        purchaseDate = equipment.purchaseDate ?? Date()
        purchasePrice = equipment.purchasePrice
        meterType = equipment.meterType
        currentMeter = equipment.currentMeter
        notes = equipment.notes
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                pendingPhotoData.append(data)
            }
        }
        selectedPhotoItems = []
    }

    private func save() {
        let saved: Equipment
        if let equipment {
            saved = equipment
        } else {
            saved = Equipment()
            modelContext.insert(saved)
        }
        saved.name = name.trimmingCharacters(in: .whitespaces)
        saved.category = category
        saved.make = make
        saved.model = model
        saved.year = year
        saved.serialOrVIN = serialOrVIN.trimmingCharacters(in: .whitespaces)
        saved.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        saved.purchasePrice = purchasePrice
        saved.meterType = meterType
        saved.currentMeter = currentMeter
        saved.notes = notes

        for data in pendingPhotoData {
            let photo = EquipmentPhoto(imageData: data)
            photo.equipment = saved
            modelContext.insert(photo)
        }
        dismiss()
    }
}
