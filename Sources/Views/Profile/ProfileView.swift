import SwiftUI

/// Profile screen. Renders the *signed-in* user when initialized
/// without a `tid`, or any other user's profile when a `tid` is
/// passed in. Self vs other-user mode toggles which toolbar items
/// show — Wallet / Settings / Activity / Bookmarks are private and
/// only appear on your own profile.
struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    /// Nil → render the signed-in user (`app.myTID`). Non-nil →
    /// render that TID. Captured at init so a sign-out doesn't
    /// retarget an already-pushed other-user view.
    let targetTID: String?

    @State private var user: User?
    @State private var tweets: [Tweet] = []
    @State private var karma: KarmaSummary?
    @State private var erProfile: ERProfile?
    @State private var followStatus: ERLinkStatus?
    @State private var loading = true
    @State private var showingWallet = false
    @State private var showingSettings = false

    init(tid: String? = nil) {
        self.targetTID = tid
    }

    /// The TID this view is actually rendering. Falls back to the
    /// signed-in user when `targetTID` is nil.
    private var resolvedTID: String? {
        targetTID ?? app.myTID
    }

    /// `true` when this is the signed-in user's own profile — drives
    /// which toolbar items render and whether to show a Follow pill.
    private var isOwnProfile: Bool {
        guard let mine = app.myTID, let shown = resolvedTID else { return targetTID == nil }
        return mine == shown
    }

    var body: some View {
        Group {
            if let tid = resolvedTID {
                List {
                    Section {
                        identityCard(tid: tid)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    if loading && tweets.isEmpty {
                        Section("Tweets") {
                            ForEach(0..<2, id: \.self) { _ in
                                TweetSkeletonRow()
                            }
                        }
                    } else if tweets.isEmpty {
                        Section("Tweets") {
                            Text("No tweets yet.")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Section("Tweets") {
                            ForEach(tweets) { tweet in
                                TweetCardView(tweet: tweet)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                EmptyStateView(
                    symbol: "person.crop.circle",
                    title: "No TID set",
                    message: "Open Settings and enter your TID to see your profile, karma, and tweets."
                )
            }
        }
        .navigationTitle(isOwnProfile ? "Profile" : profileTitle)
        .toolbar {
            if isOwnProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ActivityView()
                    } label: {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .accessibilityLabel("Activity")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BookmarksView()
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Bookmarks")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingWallet = true
                    } label: {
                        Image(systemName: "wallet.pass")
                    }
                    .accessibilityLabel("Wallet")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .refreshable { await refresh() }
        .task { load() }
        .sheet(isPresented: $showingWallet) {
            NavigationStack {
                WalletView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingWallet = false }
                        }
                    }
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
            .environmentObject(app)
        }
    }

    /// Title shown when looking at someone else's profile. Prefers
    /// `@username.tribe` if the hub returned one, else falls back to
    /// the bare TID so the back-stack reads cleanly even before the
    /// user payload arrives.
    private var profileTitle: String {
        if let username = user?.username { return "@\(username).tribe" }
        if let tid = resolvedTID { return "TID #\(tid)" }
        return "Profile"
    }

    private func identityCard(tid: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AvatarView(initial: user?.initial ?? String(tid.prefix(1)), size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user?.displayName ?? "TID #\(tid)")
                        .font(.title2.weight(.semibold))
                    if let address = user?.custodyAddress {
                        Text(short(address))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("TID #\(tid)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !isOwnProfile {
                    followPill
                }
            }

            HStack(spacing: 22) {
                Stat(label: "Following", value: "\(erProfile?.followingCount ?? user?.followingCount ?? 0)")
                Stat(label: "Followers", value: "\(erProfile?.followersCount ?? user?.followersCount ?? 0)")
                if let k = karma {
                    Stat(label: "Karma · L\(k.level)", value: "\(k.total)")
                }
            }

            if let bio = user?.profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    /// Read-only follow indicator for other-user profiles. iOS doesn't
    /// hold the Solana custody key, so it can show whether the signed-in
    /// user already follows this account but can't initiate follow /
    /// unfollow ops — those still require tribe-app.
    @ViewBuilder
    private var followPill: some View {
        if let status = followStatus {
            let label: String
            let tint: Color
            if status.isFollowing {
                label = "Following"
                tint = Color(red: 0.16, green: 0.55, blue: 0.36)
            } else if status.isPending {
                label = "Pending"
                tint = Color(red: 0.85, green: 0.55, blue: 0.10)
            } else {
                label = "Not following"
                tint = .secondary
            }
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(TribeColor.chipBackground))
        }
    }

    private func short(_ s: String) -> String {
        guard s.count > 10 else { return s }
        return "\(s.prefix(5))…\(s.suffix(5))"
    }

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard let tid = resolvedTID else { loading = false; return }
        loading = true
        async let userTask = try? app.api.fetchUser(tid)
        // Profile feed (rather than fetchTweets) so the rows include
        // retweets the user did, with retweeted_by_* metadata so the
        // card can render an "X retweeted" header.
        async let tweetsTask = try? app.api.fetchFeed(tid: tid)
        async let karmaTask = try? app.api.fetchKarma(tid)
        async let erTask = try? app.er.profile(tid)
        // Only probe the follow link when we're looking at *another*
        // user — the pill doesn't render for self-profiles anyway,
        // and the request would just answer "myself follows myself".
        async let followTask: ERLinkStatus? = {
            if isOwnProfile { return nil }
            guard let myTID = app.myTID else { return nil }
            return try? await app.er.link(followerTID: myTID, followingTID: tid)
        }()
        self.user = await userTask
        self.tweets = (await tweetsTask) ?? []
        self.karma = (await karmaTask) ?? nil
        self.erProfile = (await erTask) ?? nil
        self.followStatus = await followTask
        loading = false
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TweetSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 200, height: 12)
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
    }
}
