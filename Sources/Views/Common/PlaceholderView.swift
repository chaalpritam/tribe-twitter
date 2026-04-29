import SwiftUI

/// Minimal placeholder still in use for tabs that haven't been wired up yet.
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
                .font(.system(size: 28, weight: .black))
                .tracking(-0.5)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(TribeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer(minLength: TribeMetrics.bottomNavReservedHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TribeColor.pageBackground)
    }
}

// Tabs without dedicated screens yet.
struct MapView: View { var body: some View { PlaceholderView("Map", subtitle: "City-anchored content lands here once channel kind = 2 (city) is wired up.") } }
struct ChatView: View { var body: some View { PlaceholderView("Chat", subtitle: "Direct messages and group threads. x25519 + nacl box encryption needs porting from tribe-app.") } }
struct WalletView: View { var body: some View { PlaceholderView("Wallet", subtitle: "Receive QR + activity coming next.") } }
struct SearchView: View { var body: some View { PlaceholderView("Search", subtitle: "Cross-primitive search lands shortly.") } }
