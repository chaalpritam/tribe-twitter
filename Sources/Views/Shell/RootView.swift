import SwiftUI

/// Top-level container. Switches between the seven tabs the
/// tribeapp.wtf design exposes and overlays a central + button.
/// The actual nav bar is `BottomNavBar`; pushed-detail screens
/// live inside each tab's NavigationStack.
struct RootView: View {
    @State private var tab: Tab = .home
    @State private var presentingCreate = false

    var body: some View {
        ZStack(alignment: .bottom) {
            currentTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .ignoresSafeArea(.container, edges: .top)

            BottomNavBar(
                selected: $tab,
                onCreateTap: { presentingCreate = true }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $presentingCreate) {
            CreatePlaceholderView()
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var currentTab: some View {
        switch tab {
        case .home: HomeFeedView()
        case .explore: ExploreView()
        case .map: MapView()
        case .tribes: TribesView()
        case .chat: ChatView()
        case .profile: ProfileView()
        }
    }
}

private struct CreatePlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color(white: 0.9))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
            Text("Create")
                .font(.system(size: 22, weight: .black, design: .default))
                .tracking(-0.5)
            Text("Compose tweets, polls, events, tasks and crowdfunds. Wiring this up needs the signed-envelope path to be ported from tribe-app/src/lib/messages.ts to Swift.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("Close") { dismiss() }
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView().environmentObject(AppState())
}
