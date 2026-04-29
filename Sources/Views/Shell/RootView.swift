import SwiftUI

/// Top-level shell. Five-tab TabView following Apple HIG: Home,
/// Explore, Tribes, Activity, Profile. Each tab owns its own
/// NavigationStack so push transitions stay isolated per-tab.
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeFeedView() }
                .tabItem { Label("Home", systemImage: "house") }

            NavigationStack { ExploreView() }
                .tabItem { Label("Explore", systemImage: "safari") }

            NavigationStack { TribesView() }
                .tabItem { Label("Tribes", systemImage: "person.3") }

            NavigationStack { NotificationsView() }
                .tabItem { Label("Activity", systemImage: "bell") }

            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootView().environmentObject(AppState())
}
