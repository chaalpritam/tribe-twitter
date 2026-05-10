import SwiftUI

/// Followers / following list pushed from the profile stats row.
/// Shape mirrors Explore's "See all" people destination — Twitter-
/// style row with avatar, name, @handle, bio, and a Follow capsule
/// — so the tap path is consistent across the app.
///
/// The hub surfaces these as `/v1/users/:tid/followers` and
/// `/v1/users/:tid/following`. If the deployed hub doesn't have
/// those wrapped yet, the view degrades gracefully to an explainer
/// instead of a noisy error.
struct FollowListView: View {
    enum Mode: String, Hashable, Identifiable {
        case followers, following
        var id: String { rawValue }
    }

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var userAvatars: UserAvatarCache

    let tid: String
    let mode: Mode

    @State private var users: [User] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selectedTID: String?

    private var title: String {
        switch mode {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }

    var body: some View {
        Group {
            if loading && users.isEmpty {
                List {
                    ForEach(0..<5, id: \.self) { _ in
                        FollowSkeletonRow()
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            } else if let error, users.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load \(title.lowercased())",
                    message: error,
                    action: ("Retry", load)
                )
            } else if users.isEmpty {
                EmptyStateView(
                    symbol: mode == .followers ? "person.2" : "person.2.fill",
                    title: mode == .followers ? "No followers yet" : "Not following anyone yet",
                    message: nil
                )
            } else {
                List {
                    ForEach(users) { user in
                        FollowListRow(user: user)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedTID = user.tid }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedTID) { tid in
            ProfileView(tid: tid)
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
            let fetched: [User]
            switch mode {
            case .followers:
                fetched = try await app.api.fetchFollowers(tid)
            case .following:
                fetched = try await app.api.fetchFollowing(tid)
            }
            users = fetched
            seedAvatarCache(fetched)
        } catch HubError.statusCode(404, _) {
            // Hub doesn't expose the list endpoint — derive the list
            // from the ER server's per-pair link status. Costs one
            // /v1/users + N /v1/link round trips, which is fine for
            // small graphs. Catches everyone the hub knows about who
            // currently has an active link to / from this TID.
            await fallbackViaERLinks()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    @MainActor
    private func fallbackViaERLinks() async {
        let candidates: [User]
        do {
            candidates = try await app.api.fetchUsers(limit: 200)
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard !candidates.isEmpty else {
            users = []
            return
        }
        let resolved = await withTaskGroup(of: User?.self) { group in
            let myTID = self.tid
            let mode = self.mode
            for candidate in candidates {
                if candidate.tid == myTID { continue }
                group.addTask { [er = app.er] in
                    // Followers of myTID: candidate follows myTID.
                    // Following: myTID follows candidate.
                    let (follower, following): (String, String) = (mode == .followers)
                        ? (candidate.tid, myTID)
                        : (myTID, candidate.tid)
                    let status = try? await er.link(
                        followerTID: follower,
                        followingTID: following
                    )
                    return status?.isFollowing == true ? candidate : nil
                }
            }
            var result: [User] = []
            for await u in group {
                if let u { result.append(u) }
            }
            return result
        }
        users = resolved.sorted { lhs, rhs in
            (lhs.username ?? lhs.tid) < (rhs.username ?? rhs.tid)
        }
        seedAvatarCache(resolved)
    }

    @MainActor
    private func seedAvatarCache(_ list: [User]) {
        for u in list {
            if let raw = u.profile?.pfpUrl,
               let url = app.api.resolveMediaURL(raw) {
                userAvatars.record(tid: u.tid, pfpUrl: url)
            }
        }
    }
}

private struct FollowListRow: View {
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
}

private struct FollowSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color(.tertiarySystemFill)).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 140, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 90, height: 9)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 11)
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
