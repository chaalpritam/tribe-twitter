import SwiftUI

/// Top-level shell. Routes between Onboarding and the main TabView
/// based on AppState.phase. Each tab owns its own NavigationStack so
/// push transitions stay isolated per-tab.
struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Group {
            switch app.phase {
            case .onboarding:
                OnboardingFlow()
            case .ready:
                MainTabs()
            }
        }
        .tint(TribeColor.brand)
        .animation(.easeInOut(duration: 0.2), value: app.phase)
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { HomeFeedView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { ExploreView() }
                .tabItem { Label("Explore", systemImage: "safari.fill") }

            NavigationStack { TribesView() }
                .tabItem { Label("Tribes", systemImage: "person.3.fill") }

            NavigationStack { MessagesView() }
                .tabItem { Label("Messages", systemImage: "envelope.fill") }

            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
    }
}

#Preview {
    RootView().environmentObject(AppState())
}
