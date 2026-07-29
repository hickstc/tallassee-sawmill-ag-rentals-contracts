import SwiftUI

// MARK: - Editable lumber pricing

/// User-adjustable board-foot prices. Pine is priced by size band; other species are flat.
struct LumberPricing: Codable, Equatable {
    var pineBandRates: [Double]
    var defaultPineRate: Double
    var cypress: Double
    var cedar: Double
    var whiteOak: Double
    var redOak: Double
    var hickory: Double
    var poplar: Double

    static let storageKey = "lumberPricing"

    /// Defaults come from the built-in website pricing.
    static var defaults: LumberPricing {
        LumberPricing(
            pineBandRates: SawmillPricing.pineBands.map { $0.rate },
            defaultPineRate: SawmillPricing.defaultPineRate,
            cypress: 4.50,
            cedar: 4.00,
            whiteOak: 3.74,
            redOak: 3.00,
            hickory: 3.00,
            poplar: 1.85
        )
    }

    /// The saved pricing, or defaults if none saved / shape changed.
    static var current: LumberPricing {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(LumberPricing.self, from: data),
              decoded.pineBandRates.count == SawmillPricing.pineBands.count else {
            return defaults
        }
        return decoded
    }

    static func save(_ pricing: LumberPricing) {
        if let data = try? JSONEncoder().encode(pricing) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func pineBandRate(at index: Int) -> Double {
        pineBandRates.indices.contains(index) ? pineBandRates[index] : defaultPineRate
    }

    func flatRate(for species: WoodSpecies) -> Double {
        switch species {
        case .pine: return defaultPineRate
        case .cypress: return cypress
        case .cedar: return cedar
        case .whiteOak: return whiteOak
        case .redOak: return redOak
        case .hickory: return hickory
        case .poplar: return poplar
        }
    }
}

// MARK: - Editor (Settings)

struct LumberPricingEditor: View {
    @State private var pricing = LumberPricing.current

    var body: some View {
        Form {
            Section {
                ForEach(SawmillPricing.pineBands.indices, id: \.self) { index in
                    HStack {
                        Text(SawmillPricing.pineBands[index].label)
                            .font(.caption)
                        Spacer(minLength: 8)
                        Text("$")
                        TextField("0.00", value: $pricing.pineBandRates[index], format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70)
                        Text("/BF").font(.caption).foregroundStyle(.secondary)
                    }
                }
                rateRow("Default (no size match)", value: $pricing.defaultPineRate)
            } header: {
                Text("Pine — by size")
            } footer: {
                Text("Sizes are matched automatically; edit the price for each band.")
            }

            Section("Other Species — $/BF (true size)") {
                rateRow("Cypress", value: $pricing.cypress)
                rateRow("Cedar", value: $pricing.cedar)
                rateRow("White Oak", value: $pricing.whiteOak)
                rateRow("Red Oak", value: $pricing.redOak)
                rateRow("Hickory", value: $pricing.hickory)
                rateRow("Poplar", value: $pricing.poplar)
            }

            Section {
                Button(role: .destructive) {
                    pricing = LumberPricing.defaults
                } label: {
                    Label("Reset to Default Prices", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Lumber Prices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onChange(of: pricing) { _, newValue in
            LumberPricing.save(newValue)
        }
    }

    private func rateRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("$")
            TextField("0.00", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 70)
            Text("/BF").font(.caption).foregroundStyle(.secondary)
        }
    }
}
