import SwiftUI

@main
struct TribeIOSApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Bump URLCache.shared so URLSession's HTTP cache (used by
        // image fetches) can hold avatars across launches without
        // hitting the network. NSCache in ImageCache holds decoded
        // UIImages on top of that for instant scroll-back rendering.
        ImageCache.configureURLCache()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                // Cache is also injected so views can observe its
                // @Published sets directly — `let` properties on
                // AppState don't propagate inner-object changes
                // through the EnvironmentObject machinery.
                .environmentObject(appState.interactions)
                .environmentObject(appState.tipStats)
                .environmentObject(appState.userAvatars)
        }
    }
}
