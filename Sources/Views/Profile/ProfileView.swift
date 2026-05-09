import SwiftUI

/// Profile screen. Renders the *signed-in* user when initialized
/// without a `tid`, or any other user's profile when a `tid` is
/// passed in. Self vs other-user mode toggles which toolbar items
/// show — Wallet / Settings / Activity / Bookmarks are private and
/// only appear on your own profile.
struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var userAvatars: UserAvatarCache
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
    @State private var selectedTab: ProfileTab = .tweets

    enum ProfileTab: String, CaseIterable, Identifiable {
        case tweets = "Tweets"
        case tips = "Tips"
        var id: String { rawValue }
    }

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
                    profileHeader(tid: tid)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    tabBar
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemBackground))

                    switch selectedTab {
                    case .tweets:
                        tweetsSection
                    case .tips:
                        tipsSection
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
            } else {
                EmptyStateView(
                    symbol: "person.crop.circle",
                    title: "No TID set",
                    message: "Open Settings and enter your TID to see your profile, karma, and tweets."
                )
            }
        }
        .navigationTitle(isOwnProfile ? "Profile" : profileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwnProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            ActivityView()
                        } label: {
                            Label("Activity", systemImage: "list.bullet.clipboard")
                        }
                        NavigationLink {
                            BookmarksView()
                        } label: {
                            Label("Bookmarks", systemImage: "bookmark")
                        }
                        Button {
                            showingWallet = true
                        } label: {
                            Label("Wallet", systemImage: "wallet.pass")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
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

    // MARK: - Header (banner + avatar + meta)

    private func profileHeader(tid: String) -> some View {
        let seed = user?.username ?? tid
        return VStack(alignment: .leading, spacing: 0) {
            // Banner — gradient seeded by the user so each profile
            // has a stable, distinct color until we wire up uploads.
            ZStack(alignment: .bottomLeading) {
                TribeColor.avatarGradient(seed: "banner-\(seed)")
                    .frame(height: 140)
                    .clipped()
            }
            .frame(maxWidth: .infinity)

            // Avatar overlapping bottom of banner + action button on the right
            HStack(alignment: .bottom) {
                AvatarView(
                    initial: user?.initial ?? String(tid.prefix(1)),
                    size: 84,
                    pfpURL: app.api.resolveMediaURL(user?.profile?.pfpUrl),
                    seed: seed
                )
                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 4))
                .offset(y: -42)
                .padding(.leading, 16)
                .padding(.bottom, -42)

                Spacer()

                actionButton
                    .padding(.trailing, 16)
                    .padding(.top, 12)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(user?.displayName ?? "TID #\(tid)")
                        .font(.title2.weight(.bold))
                    Text(handleText(tid: tid))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let bio = user?.profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                metaRow

                statsRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isOwnProfile {
            Button {
                showingProfileEditor = true
            } label: {
                Text("Edit profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().strokeBorder(TribeColor.cardStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(app.appKey == nil)
        } else if let status = followStatus {
            followCapsule(for: status)
        }
    }

    @ViewBuilder
    private func followCapsule(for status: ERLinkStatus) -> some View {
        let label: String = status.isFollowing ? "Following" : (status.isPending ? "Pending" : "Follow")
        let isFollowingOrPending = status.isFollowing || status.isPending
        Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isFollowingOrPending ? TribeColor.brand : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isFollowingOrPending {
                        Capsule().fill(TribeColor.brand.opacity(0.12))
                    } else {
                        Capsule().fill(TribeColor.brandGradient)
                    }
                }
            )
            .overlay(
                Capsule().strokeBorder(
                    isFollowingOrPending ? TribeColor.brand.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
            )
    }

    private func handleText(tid: String) -> String {
        if let username = user?.username { return "@\(username).tribe" }
        return "@tid\(tid)"
    }

    @ViewBuilder
    private var metaRow: some View {
        let location = user?.profile?.location
        let urlString = user?.profile?.url
        let address = user?.custodyAddress

        if (location?.isEmpty == false) || (urlString?.isEmpty == false) || (address?.isEmpty == false) {
            HStack(spacing: 14) {
                if let loc = location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label(displayHost(urlString), systemImage: "link")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TribeColor.brand)
                    }
                }
                if let address, !address.isEmpty {
                    Label(short(address), systemImage: "wallet.pass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 22) {
            inlineStat(
                value: "\(erProfile?.followingCount ?? user?.followingCount ?? 0)",
                label: "Following"
            )
            inlineStat(
                value: "\(erProfile?.followersCount ?? user?.followersCount ?? 0)",
                label: "Followers"
            )
            if let k = karma {
                inlineStat(
                    value: "\(k.total)",
                    label: "Karma · L\(k.level)",
                    valueTint: TribeColor.accentAmber
                )
            }
        }
    }

    private func inlineStat(value: String, label: String, valueTint: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(valueTint)
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tab bar (Tweets / Tips)

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        Rectangle()
                            .fill(selectedTab == tab ? TribeColor.brand : Color.clear)
                            .frame(height: 3)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TribeColor.cardStroke.opacity(0.4))
                .frame(height: 0.5)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var tweetsSection: some View {
        if loading && tweets.isEmpty {
            ForEach(0..<3, id: \.self) { _ in
                TweetSkeletonRow()
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        } else if tweets.isEmpty {
            Text("No tweets yet.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
                .listRowSeparator(.hidden)
        } else {
            ForEach(tweets) { tweet in
                TweetCardView(tweet: tweet)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var tipsSection: some View {
        if tipsReceived.isEmpty && (!isOwnProfile || tipsSent.isEmpty) {
            Text("No tips yet.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
                .listRowSeparator(.hidden)
        } else {
            if !tipsReceived.isEmpty {
                Section("Received") {
                    ForEach(tipsReceived) { tip in
                        OnchainTipRow(tip: tip, role: .received)
                    }
                }
            }
            if isOwnProfile && !tipsSent.isEmpty {
                Section("Sent") {
                    ForEach(tipsSent) { tip in
                        OnchainTipRow(tip: tip, role: .sent)
                    }
                }
            }
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
        async let tweetsTask = try? app.api.fetchFeed(tid: tid)
        async let karmaTask = try? app.api.fetchKarma(tid)
        async let erTask = try? app.er.profile(tid)
        async let followTask: ERLinkStatus? = fetchFollowStatus(tid: tid)
        async let receivedTask = try? app.api.fetchOnchainTipsReceived(tid)
        async let sentTask: [OnchainTip]? = isOwnProfile
            ? (try? await app.api.fetchOnchainTipsSent(tid))
            : nil
        let resolvedUser = await userTask
        self.user = resolvedUser
        // Seed the shared avatar cache so other surfaces (feed rows,
        // DMs, tips) can render this user's pfp without their own
        // round trip.
        if let resolved = resolvedUser {
            userAvatars.record(
                tid: resolved.tid,
                pfpUrl: app.api.resolveMediaURL(resolved.profile?.pfpUrl)
            )
        }
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

    private var counterpartyTID: String {
        role == .received ? tip.senderTid : tip.recipientTid
    }

    private var explorerURL: URL? {
        URL(string: "https://explorer.solana.com/tx/\(tip.txSignature)?cluster=\(Config.solanaCluster)")
    }

    var body: some View {
        HStack(spacing: 12) {
            UserAvatar(
                tid: counterpartyTID,
                initial: initial,
                size: 36,
                seed: tip.counterpartyUsername ?? counterpartyTID
            )
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
                    .foregroundStyle(TribeColor.accentAmber)
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

private struct TweetSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color(.tertiarySystemFill)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)).frame(width: 140, height: 11)
                RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 11)
                RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)).frame(width: 220, height: 11)
            }
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
