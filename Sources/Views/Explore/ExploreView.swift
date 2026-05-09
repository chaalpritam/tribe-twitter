import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var userAvatars: UserAvatarCache
    @State private var users: [User] = []
    @State private var loading = true
    @State private var error: String?
    /// User pushed via row tap; drives navigationDestination so the
    /// row tap reaches the profile without the disclosure chevron a
    /// NavigationLink-as-row would draw, and so FollowButton inside
    /// each row stays independently tappable.
    @State private var selectedTID: String?

    var body: some View {
        Group {
            if loading && users.isEmpty {
                List {
                    ForEach(0..<5, id: \.self) { _ in
                        UserSkeleton()
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            } else if let error, users.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load users",
                    message: error,
                    action: ("Retry", load)
                )
            } else if users.isEmpty {
                EmptyStateView(
                    symbol: "person.2",
                    title: "No users yet",
                    message: "Be the first to register a Tribe identity."
                )
            } else {
                List {
                    ForEach(users) { user in
                        UserRow(user: user)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedTID = user.tid }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Explore")
        .navigationDestination(item: $selectedTID) { tid in
            ProfileView(tid: tid)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SearchView()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }
        }
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
            let fetched = try await app.api.fetchUsers()
            users = fetched
            // Seed the avatar cache with whatever pfp the list
            // endpoint already returned. /v1/users tends to omit the
            // profile sub-object (only /v1/user/:tid hydrates it),
            // so most entries here will be nil — UserAvatar will
            // fill them in lazily as each row appears.
            for u in fetched {
                if let raw = u.profile?.pfpUrl,
                   let url = app.api.resolveMediaURL(raw) {
                    userAvatars.record(tid: u.tid, pfpUrl: url)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct UserRow: View {
    let user: User

    private var handle: String {
        if let u = user.username { return "@\(u).tribe" }
        return "@tid\(user.tid)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            UserAvatar(
                tid: user.tid,
                initial: user.initial,
                size: 48,
                seed: user.username ?? user.tid
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    FollowButton(targetTID: user.tid)
                }

                if let bio = user.profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                statsRow
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TribeColor.cardStroke.opacity(0.4))
                .frame(height: 0.5)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 14) {
            inlineStat(
                value: "\(user.followingCount)",
                label: "Following"
            )
            inlineStat(
                value: "\(user.followersCount)",
                label: "Followers"
            )
        }
    }

    private func inlineStat(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UserSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color(.tertiarySystemFill)).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 140, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 90, height: 9)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 200, height: 11)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TribeColor.cardStroke.opacity(0.4))
                .frame(height: 0.5)
        }
        .redacted(reason: .placeholder)
    }
}
