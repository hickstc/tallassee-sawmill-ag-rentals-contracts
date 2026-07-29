//___FILEHEADER___

import SwiftUI

@main
struct Tallassee_Sawmill_AG___Rentals_ContractsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Shows the logo splash for 1.5 seconds before revealing the main app.
private struct RootView: View {
    @State private var showingSplash = true

    var body: some View {
        ZStack {
            ContentView()
            if showingSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.4)) {
                showingSplash = false
            }
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 400)
                .padding(40)
        }
    }
}
