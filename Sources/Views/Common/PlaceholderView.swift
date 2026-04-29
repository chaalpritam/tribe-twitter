import SwiftUI

/// Minimal placeholder used during scaffolding so each tab compiles.
/// Replaced screen-by-screen as features get built out.
struct PlaceholderView: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(title)
                .font(.system(size: 28, weight: .black, design: .default))
                .tracking(-0.5)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HomeFeedView: View { var body: some View { PlaceholderView("Home", subtitle: "Tweet feed wires up next.") } }
struct ExploreView: View { var body: some View { PlaceholderView("Explore", subtitle: "Discover people on the network.") } }
struct MapView: View { var body: some View { PlaceholderView("Map", subtitle: "City-anchored content (city channel kind).") } }
struct TribesView: View { var body: some View { PlaceholderView("Tribes", subtitle: "Channels and groups.") } }
struct ChatView: View { var body: some View { PlaceholderView("Chat", subtitle: "Direct messages and group threads.") } }
struct ProfileView: View { var body: some View { PlaceholderView("Profile", subtitle: "Your TID, karma, tweets.") } }
