import SwiftUI

// MARK: - Contract / Tool Selection

private enum ContractType: String, CaseIterable, Identifiable, Hashable {
    case rental
    case ag
    case calculator
    case orders
    case milling
    case maintenance
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rental: return "Rental Agreement"
        case .ag: return "Agricultural Services"
        case .calculator: return "Board Foot Calculator"
        case .orders: return "Lumber Orders"
        case .milling: return "Customer Logs Milled"
        case .maintenance: return "Maintenance"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .rental: return "house.fill"
        case .ag: return "leaf.fill"
        case .calculator: return "ruler.fill"
        case .orders: return "list.bullet.rectangle"
        case .milling: return "tree.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(ContractType.allCases) { type in
                    NavigationLink(value: type) {
                        Label(type.title, systemImage: type.systemImage)
                            .font(.headline)
                            .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Tallassee Sawmill")
            .navigationDestination(for: ContractType.self) { type in
                destination(for: type)
            }
        }
    }

    @ViewBuilder
    private func destination(for type: ContractType) -> some View {
        switch type {
        case .rental:
            RentalAgreementView()
        case .ag:
            AgriculturalServicesView()
        case .calculator:
            BoardFootCalculatorView()
                .navigationTitle(type.title)
        case .orders:
            LumberOrdersView()
        case .milling:
            MillingJobsView()
        case .maintenance:
            MaintenanceView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Board Foot Calculator

private struct BoardFootCalculatorView: View {
    @State private var thicknessIn = "1"
    @State private var widthIn = "6"
    @State private var lengthFt = "8"
    @State private var quantity = "1"

    private var boardFeet: Double {
        let t = Double(thicknessIn) ?? 0
        let w = Double(widthIn) ?? 0
        let l = Double(lengthFt) ?? 0
        let qty = Double(quantity) ?? 0
        return max(0, (t * w * l) / 12.0 * qty)
    }

    var body: some View {
        Form {
            Section("Dimensions") {
                LabeledContent("Thickness (in)") {
                    TextField("1", text: $thicknessIn)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Width (in)") {
                    TextField("6", text: $widthIn)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Length (ft)") {
                    TextField("8", text: $lengthFt)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Quantity") {
                    TextField("1", text: $quantity)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Result") {
                LabeledContent("Board Feet") {
                    Text(boardFeet.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.headline)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
