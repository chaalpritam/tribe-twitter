import SwiftUI

@main
struct TribeIOSApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                // Cache is also injected so views can observe its
                // @Published sets directly — `let` properties on
                // AppState don't propagate inner-object changes
                // through the EnvironmentObject machinery.
                .environmentObject(appState.interactions)
        }
    }
}
