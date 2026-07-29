import SwiftUI

// MARK: - Catalog model

/// A single price tier for a rental item, e.g. "Daily" — $340.
struct RentalTier: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String = ""
    var price: String = ""
}

/// A piece of rentable equipment with one or more price tiers.
struct RentalItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = ""
    var tiers: [RentalTier] = []
}

// MARK: - Catalog storage

enum RentalCatalogStorage {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("rental_catalog.json")
    }

    static func load() -> [RentalItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([RentalItem].self, from: data) else {
            return defaultCatalog
        }
        return items
    }

    static func save(_ items: [RentalItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Seeded from current QuickBooks pricing; fully editable in Settings.
    static let defaultCatalog: [RentalItem] = [
        RentalItem(name: "Mini Excavator", tiers: [
            RentalTier(label: "Daily", price: "340"),
            RentalTier(label: "Weekend", price: "425"),
            RentalTier(label: "Weekly", price: "950"),
            RentalTier(label: "2 Weeks", price: "1800"),
            RentalTier(label: "Monthly", price: "2900")
        ]),
        RentalItem(name: "Trailer", tiers: [
            RentalTier(label: "Daily", price: "75")
        ])
    ]
}

// MARK: - Catalog editor (Settings)

struct RentalItemsEditor: View {
    @State private var items: [RentalItem] = []
    @State private var loaded = false

    var body: some View {
        List {
            ForEach($items) { $item in
                Section {
                    TextField("Item name", text: $item.name)
                        .font(.headline)
                        .textInputAutocapitalization(.words)

                    ForEach($item.tiers) { $tier in
                        HStack {
                            TextField("Label (e.g. Daily)", text: $tier.label)
                            Spacer(minLength: 8)
                            Text("$")
                            TextField("0", text: $tier.price)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                        }
                    }
                    .onDelete { item.tiers.remove(atOffsets: $0) }

                    Button {
                        item.tiers.append(RentalTier())
                    } label: {
                        Label("Add Rate Tier", systemImage: "plus")
                    }

                    Button(role: .destructive) {
                        items.removeAll { $0.id == item.id }
                    } label: {
                        Label("Remove This Item", systemImage: "trash")
                    }
                }
            }

            Section {
                Button {
                    items.append(RentalItem(name: "", tiers: [RentalTier(label: "Daily", price: "")]))
                } label: {
                    Label("Add Rental Item", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Rental Items & Rates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear {
            if !loaded {
                items = RentalCatalogStorage.load()
                loaded = true
            }
        }
        .onChange(of: items) { _, newValue in
            RentalCatalogStorage.save(newValue)
        }
    }
}
