//
//  InventoryView.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Inventory management: stock levels for every part and fluid with search,
//  filters, quick "receive" (records a purchase and bumps stock), and quick
//  stock adjustment for corrections after a shelf count.
//

import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Part.partDescription) private var parts: [Part]

    @State private var searchText = ""
    @State private var scope: PartLibraryScope = .all
    @State private var receivingPart: Part?
    @State private var adjustingPart: Part?
    @State private var stockInput: Double?

    private var filteredParts: [Part] {
        parts.filter { scope.includes($0) && $0.matches(searchText) }
    }

    /// Estimated value of everything on the shelf (quantity × last price).
    private var totalValue: Decimal {
        parts.reduce(Decimal(0)) { total, part in
            guard let price = part.lastPrice else { return total }
            return total + price * Decimal(part.quantityOnHand)
        }
    }

    private var lowStockCount: Int { parts.filter(\.isLowStock).count }

    var body: some View {
        List {
            summarySection

            Section {
                ForEach(filteredParts, id: \.uuid) { part in
                    NavigationLink {
                        PartDetailView(part: part)
                    } label: {
                        PartRow(part: part)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            receivingPart = part
                        } label: {
                            Label("Receive", systemImage: "plus.square.on.square")
                        }
                        .tint(.green)
                        Button {
                            stockInput = part.quantityOnHand
                            adjustingPart = part
                        } label: {
                            Label("Adjust", systemImage: "slider.horizontal.3")
                        }
                        .tint(.blue)
                    }
                }
            } footer: {
                Text("Swipe a row to receive stock or adjust the count. Completing a service subtracts used parts automatically.")
            }
        }
        .overlay {
            if filteredParts.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Nothing Here",
                        systemImage: "shippingbox",
                        description: Text("No items match this filter.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText, prompt: "OEM #, cross ref, description")
        .navigationTitle("Inventory")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter", selection: $scope) {
                        ForEach(PartLibraryScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                } label: {
                    Label("Filter",
                          systemImage: scope == .all
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .sheet(item: $receivingPart) { part in
            NavigationStack {
                PartPurchaseFormView(part: part)
            }
        }
        .alert("Adjust Stock", isPresented: .init(
            get: { adjustingPart != nil },
            set: { if !$0 { adjustingPart = nil } }
        )) {
            TextField("On hand (\(adjustingPart?.unit ?? "ea"))", value: $stockInput, format: .number)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let part = adjustingPart, let stockInput {
                    part.quantityOnHand = max(0, stockInput)
                }
                adjustingPart = nil
            }
            Button("Cancel", role: .cancel) { adjustingPart = nil }
        } message: {
            Text("Set the counted quantity for “\(adjustingPart?.partDescription ?? "")”.")
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                InventoryStat(
                    value: "\(parts.count)",
                    label: "Items",
                    color: .blue
                )
                InventoryStat(
                    value: totalValue.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")),
                    label: "Stock Value",
                    color: .green
                )
                InventoryStat(
                    value: "\(lowStockCount)",
                    label: "Low Stock",
                    color: lowStockCount > 0 ? .red : .green
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
}

/// A compact stat tile for the inventory summary strip.
private struct InventoryStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
