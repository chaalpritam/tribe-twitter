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
    @State private var tipsReceived: [OnchainTip] = []
    @State private var tipsSent: [OnchainTip] = []
    @State private var loading = true
    @State private var showingWallet = false
    @State private var showingSettings = false
    @State private var showingProfileEditor = false

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

                    if !tipsReceived.isEmpty {
                        Section("Tips received") {
                            ForEach(tipsReceived) { tip in
                                OnchainTipRow(tip: tip, role: .received)
                            }
                        }
                    }

                    if isOwnProfile && !tipsSent.isEmpty {
                        Section("Tips sent") {
                            ForEach(tipsSent) { tip in
                                OnchainTipRow(tip: tip, role: .sent)
                            }
                        }
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
        .sheet(isPresented: $showingProfileEditor) {
            NavigationStack {
                ProfileEditorView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingProfileEditor = false }
                        }
                    }
            }
            .environmentObject(app)
        }
        .onChange(of: showingProfileEditor) { _, isShown in
            // Reload after the editor closes so any field edits the
            // user just published show up in the card without
            // needing to pull-to-refresh.
            if !isShown { Task { await refresh() } }
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
                if isOwnProfile {
                    Button {
                        showingProfileEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(TribeColor.chipBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(app.appKey == nil)
                } else {
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

            HStack(spacing: 16) {
                if let location = user?.profile?.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let urlString = user?.profile?.url,
                   !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label(displayHost(urlString), systemImage: "link")
                            .font(.caption.weight(.medium))
                    }
                }
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
            let content = followPillContent(for: status)
            Text(content.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(content.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(TribeColor.chipBackground))
        }
    }

    private func followPillContent(for status: ERLinkStatus) -> (label: String, tint: Color) {
        if status.isFollowing {
            return ("Following", Color(red: 0.16, green: 0.55, blue: 0.36))
        } else if status.isPending {
            return ("Pending", Color(red: 0.85, green: 0.55, blue: 0.10))
        } else {
            return ("Not following", .secondary)
        }
    }

    private func short(_ s: String) -> String {
        guard s.count > 10 else { return s }
        return "\(s.prefix(5))…\(s.suffix(5))"
    }

    /// Drop the scheme so the link chip on the profile card reads
    /// `example.com/path` rather than `https://example.com/path`.
    /// Falls through to the original string if URL parsing fails.
    private func displayHost(_ s: String) -> String {
        guard let url = URL(string: s), let host = url.host else { return s }
        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        return host + path
    }

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func fetchFollowStatus(tid: String) async -> ERLinkStatus? {
        if isOwnProfile { return nil }
        guard let myTID = app.myTID else { return nil }
        return try? await app.er.link(followerTID: myTID, followingTID: tid)
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
        async let followTask: ERLinkStatus? = fetchFollowStatus(tid: tid)
        // Tips received are public on every profile; sent are private,
        // so only fetch them when the viewer is the same user.
        async let receivedTask = try? app.api.fetchOnchainTipsReceived(tid)
        async let sentTask: [OnchainTip]? = isOwnProfile
            ? (try? await app.api.fetchOnchainTipsSent(tid))
            : nil
        self.user = await userTask
        self.tweets = (await tweetsTask) ?? []
        self.karma = (await karmaTask) ?? nil
        self.erProfile = (await erTask) ?? nil
        self.followStatus = await followTask
        self.tipsReceived = (await receivedTask) ?? []
        self.tipsSent = (await sentTask) ?? []
        loading = false
    }
}

/// Row in the on-chain tips section. Tap → Solana explorer for the
/// settling tx. Counterparty initial / username comes from the join
/// the hub does on tids.username (nil → fall back to TID #N).
private struct OnchainTipRow: View {
    enum Role { case received, sent }
    let tip: OnchainTip
    let role: Role

    private var counterpartyTitle: String {
        if let u = tip.counterpartyUsername, !u.isEmpty {
            return "@\(u).tribe"
        }
        return "TID #\(role == .received ? tip.senderTid : tip.recipientTid)"
    }

    private var initial: String {
        if let u = tip.counterpartyUsername, let first = u.first {
            return String(first).uppercased()
        }
        let tid = role == .received ? tip.senderTid : tip.recipientTid
        return String(tid.prefix(1))
    }

    private var explorerURL: URL? {
        URL(string: "https://explorer.solana.com/tx/\(tip.txSignature)?cluster=\(Config.solanaCluster)")
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initial: initial, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(role == .received ? "From \(counterpartyTitle)" : "To \(counterpartyTitle)")
                    .font(.subheadline.weight(.medium))
                Text(RelativeTime.short(tip.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(tip.formattedSol) SOL")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let url = explorerURL {
                    Link(destination: url) {
                        Label("Explorer", systemImage: "arrow.up.right.square")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
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
