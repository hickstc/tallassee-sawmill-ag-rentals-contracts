import SwiftUI

// MARK: - Contract / Tool Selection

/// Every module the dashboard can route to. Internal (not private) because
/// HomeDashboardView builds its navigation links from these cases.
enum ContractType: String, CaseIterable, Identifiable, Hashable {
    case rental
    case ag
    case calculator
    case orders
    case scheduler
    case milling
    case maintenance
    case customers
    case financials
    case allPhotos
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rental: return "Rental Agreement"
        case .ag: return "Agricultural Services"
        case .calculator: return "Board Foot Calculator"
        case .orders: return "Lumber Orders"
        case .scheduler: return "Scheduler"
        case .milling: return "Customer Logs Milled"
        case .maintenance: return "Maintenance"
        case .customers: return "Customers"
        case .financials: return "Financial Report"
        case .allPhotos: return "All Job Photos"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .rental: return "house.fill"
        case .ag: return "leaf.fill"
        case .calculator: return "ruler.fill"
        case .orders: return "list.bullet.rectangle"
        case .scheduler: return "calendar"
        case .milling: return "tree.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .customers: return "person.2.fill"
        case .financials: return "chart.bar.fill"
        case .allPhotos: return "photo.on.rectangle"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    var body: some View {
        NavigationStack {
            HomeDashboardView()
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
        case .scheduler:
            SchedulerView()
        case .milling:
            MillingJobsView()
        case .maintenance:
            MaintenanceView()
        case .customers:
            CustomersView()
        case .financials:
            FinancialReportView()
        case .allPhotos:
            AllJobsMediaBrowser()
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
