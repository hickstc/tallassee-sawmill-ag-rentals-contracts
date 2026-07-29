import SwiftUI

struct SettingsView: View {
    @AppStorage("salesTaxPercent") private var taxPercent: Double = 6.5

    var body: some View {
        List {
            Section("Records") {
                NavigationLink {
                    CustomersView()
                } label: {
                    Label("Customers", systemImage: "person.2.fill")
                }
                NavigationLink {
                    FinancialReportView()
                } label: {
                    Label("Financial Report", systemImage: "chart.pie.fill")
                }
            }

            Section("Rentals") {
                NavigationLink {
                    RentalItemsEditor()
                } label: {
                    Label("Rental Items & Rates", systemImage: "wrench.and.screwdriver.fill")
                }
            }

            Section("Lumber") {
                NavigationLink {
                    LumberPricingEditor()
                } label: {
                    Label("Board-Foot Prices", systemImage: "dollarsign.square.fill")
                }
                NavigationLink {
                    MillingRatesEditor()
                } label: {
                    Label("Milling Rates", systemImage: "dollarsign.circle.fill")
                }
            }

            Section("Pricing") {
                HStack {
                    Label("Sales Tax", systemImage: "percent")
                    Spacer()
                    TextField("6.5", value: $taxPercent, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 60)
                    Text("%")
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
