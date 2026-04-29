import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var app: AppState
    @State private var users: [User] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader("Explore", subtitle: "Discover people on the network")

                LazyVStack(spacing: 10) {
                    if loading {
                        ForEach(0..<5, id: \.self) { _ in UserSkeleton() }
                    } else if let error {
                        EmptyStateView(
                            symbol: "wifi.exclamationmark",
                            title: "Couldn't load users",
                            body: error,
                            action: ("Retry", load)
                        )
                        .padding(.horizontal, 16)
                    } else if users.isEmpty {
                        EmptyStateView(
                            symbol: "person.2",
                            title: "No users yet",
                            body: "Be the first to register a Tribe identity."
                        )
                        .padding(.horizontal, 16)
                    } else {
                        ForEach(users) { user in
                            UserRow(user: user)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: TribeMetrics.bottomNavReservedHeight)
            }
        }
        .background(TribeColor.pageBackground)
        .refreshable { await refresh() }
        .task { load() }
    }

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        loading = users.isEmpty
        error = nil
        do {
            users = try await app.api.fetchUsers()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct UserRow: View {
    let user: User

    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                AvatarView(initial: user.initial, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.system(size: 15, weight: .bold))
                    Text(walletShort)
                        .font(.system(size: 12))
                        .foregroundStyle(TribeColor.textSecondary)
                    Text("\(user.followersCount) followers · \(user.followingCount) following")
                        .font(.system(size: 11))
                        .foregroundStyle(TribeColor.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var walletShort: String {
        let s = user.custodyAddress
        guard s.count > 8 else { return s }
        return "\(s.prefix(4))…\(s.suffix(4))"
    }
}

private struct UserSkeleton: View {
    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Circle().fill(TribeColor.chipBackground).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 140, height: 11)
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 90, height: 9)
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 160, height: 9)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }
}
