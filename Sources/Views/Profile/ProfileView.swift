import SwiftUI

/// Profile screen. Renders the *signed-in* user when initialized
/// without a `tid`, or any other user's profile when a `tid` is
/// passed in. Self vs other-user mode toggles which toolbar items
/// show — Wallet / Settings / Activity / Bookmarks are private and
/// only appear on your own profile.
struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var userAvatars: UserAvatarCache
    @EnvironmentObject private var interactions: InteractionCache
    /// Nil → render the signed-in user (`app.myTID`). Non-nil →
    /// render that TID. Captured at init so a sign-out doesn't
    /// retarget an already-pushed other-user view.
    let targetTID: String?

    @State private var user: User?
    @State private var tweets: [Tweet] = []
    @State private var karma: KarmaSummary?
    @State private var erProfile: ERProfile?
    @State private var followStatus: ERLinkStatus?
    @State private var likedTweets: [Tweet] = []
    @State private var likedLoaded = false
    @State private var likedLoading = false
    @State private var loading = true
    @State private var showingSettings = false
    @State private var showingProfileEditor = false
    @State private var selectedTab: ProfileTab = .tweets
    @State private var selectedMediaTweet: Tweet?
    @State private var followListMode: FollowListView.Mode?
    @State private var showingKarma = false

    enum ProfileTab: String, CaseIterable, Identifiable {
        case tweets = "Tweets"
        case media = "Media"
        case likes = "Likes"
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
                    case .media:
                        mediaSection
                    case .likes:
                        likesSection
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .onChange(of: selectedTab) { _, new in
                    if new == .likes && isOwnProfile && !likedLoaded {
                        Task { await loadLiked() }
                    }
                }
                .navigationDestination(item: $selectedMediaTweet) { t in
                    TweetDetailView(tweet: t)
                }
                .navigationDestination(item: $followListMode) { mode in
                    if let tid = resolvedTID {
                        FollowListView(tid: tid, mode: mode)
                    }
                }
                .sheet(isPresented: $showingKarma) {
                    if let k = karma {
                        NavigationStack {
                            KarmaSheet(karma: k)
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Done") { showingKarma = false }
                                    }
                                }
                        }
                        .presentationDetents([.medium, .large])
                    }
                }
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
                        NavigationLink {
                            TipsView()
                        } label: {
                            Label("Tips", systemImage: "dollarsign.circle")
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

            VStack(alignment: .leading, spacing: 14) {
                identityBlock(tid: tid)

                if let bio = user?.profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                metaRow

                joinedRow

                statsRow
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    /// Display name with a shortened custody-address chip beside it,
    /// then @handle below. The chip's copy button writes the full
    /// address to the pasteboard and flashes a checkmark for 1.5s.
    @ViewBuilder
    private func identityBlock(tid: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(user?.displayName ?? "TID #\(tid)")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let address = user?.custodyAddress, !address.isEmpty {
                    addressChip(address)
                }
                Spacer(minLength: 0)
            }
            Text(handleText(tid: tid))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @State private var addressCopied = false

    private func addressChip(_ address: String) -> some View {
        HStack(spacing: 4) {
            Text(shortAddress(address))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                UIPasteboard.general.string = address
                addressCopied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run { addressCopied = false }
                }
            } label: {
                Image(systemName: addressCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(addressCopied ? TribeColor.accentEmerald : TribeColor.brand)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(addressCopied ? "Copied" : "Copy address")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(TribeColor.chipBackground))
    }

    private func shortAddress(_ s: String) -> String {
        guard s.count > 10 else { return s }
        return "\(s.prefix(4))…\(s.suffix(4))"
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
    private var joinedRow: some View {
        if let registeredAt = user?.registeredAt {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Joined \(joinedDateLabel(registeredAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func joinedDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    @ViewBuilder
    private var metaRow: some View {
        let location = user?.profile?.location
        let urlString = user?.profile?.url

        if (location?.isEmpty == false) || (urlString?.isEmpty == false) {
            HStack(spacing: 18) {
                if let loc = location, !loc.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TribeColor.accentTeal)
                        Text(loc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TribeColor.brand)
                            Text(displayHost(urlString))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(TribeColor.brand)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 22) {
            Button {
                followListMode = .following
            } label: {
                inlineStat(
                    value: "\(erProfile?.followingCount ?? user?.followingCount ?? 0)",
                    label: "Following"
                )
            }
            .buttonStyle(.plain)

            Button {
                followListMode = .followers
            } label: {
                inlineStat(
                    value: "\(erProfile?.followersCount ?? user?.followersCount ?? 0)",
                    label: "Followers"
                )
            }
            .buttonStyle(.plain)

            if let k = karma {
                Button {
                    showingKarma = true
                } label: {
                    inlineStat(
                        value: "\(k.total)",
                        label: "Karma · L\(k.level)",
                        valueTint: TribeColor.accentAmber
                    )
                }
                .buttonStyle(.plain)
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

    /// Three-column image grid of every embed across this user's
    /// tweets. Tapping a tile pushes the parent tweet's detail view.
    @ViewBuilder
    private var mediaSection: some View {
        if loading && tweets.isEmpty {
            mediaGridSkeleton
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        } else if mediaItems.isEmpty {
            Text("No media yet.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
                .listRowSeparator(.hidden)
        } else {
            mediaGrid
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
    }

    private var mediaGrid: some View {
        let columns: [GridItem] = Array(
            repeating: GridItem(.flexible(), spacing: 2),
            count: 3
        )
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(mediaItems) { item in
                Button {
                    selectedMediaTweet = item.tweet
                } label: {
                    CachedAsyncImage(url: item.url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(.tertiarySystemFill)
                    }
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 124)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private var mediaGridSkeleton: some View {
        let columns: [GridItem] = Array(
            repeating: GridItem(.flexible(), spacing: 2),
            count: 3
        )
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<6, id: \.self) { _ in
                Color(.tertiarySystemFill)
                    .frame(height: 124)
            }
        }
        .padding(.top, 2)
        .redacted(reason: .placeholder)
    }

    private struct MediaItem: Identifiable {
        let url: URL
        let tweet: Tweet
        var id: String { "\(tweet.id)|\(url.absoluteString)" }
    }

    private var mediaItems: [MediaItem] {
        tweets.flatMap { tweet in
            (tweet.embeds ?? [])
                .compactMap { app.api.resolveMediaURL($0) }
                .map { MediaItem(url: $0, tweet: tweet) }
        }
    }

    /// Tweets the *signed-in* user has liked. The hub has no public
    /// endpoint for "tweets liked by user X", so on other-user
    /// profiles we render an explainer rather than fake the data.
    @ViewBuilder
    private var likesSection: some View {
        if !isOwnProfile {
            VStack(spacing: 8) {
                Image(systemName: "heart")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("Likes are private")
                    .font(.subheadline.weight(.semibold))
                Text("Other users' likes aren't surfaced by the hub yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .padding(.horizontal, 32)
            .listRowSeparator(.hidden)
        } else if likedLoading && likedTweets.isEmpty {
            ForEach(0..<3, id: \.self) { _ in
                TweetSkeletonRow()
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        } else if likedTweets.isEmpty {
            Text("No liked tweets yet.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
                .listRowSeparator(.hidden)
        } else {
            ForEach(likedTweets) { tweet in
                TweetCardView(tweet: tweet)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
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
        loading = false
        // If the user lands directly on the Likes tab (e.g., a
        // refresh after a previous session left it selected), kick
        // off the like-fetch alongside everything else.
        if selectedTab == .likes && isOwnProfile && !likedLoaded {
            await loadLiked()
        }
    }

    /// Resolve the signed-in user's liked tweet hashes (from
    /// InteractionCache) into full Tweet payloads. The hub doesn't
    /// have a single "fetch tweets by hashes" endpoint, so we fan
    /// out fetchTweet(hash:) in a TaskGroup and drop failures.
    @MainActor
    private func loadLiked() async {
        guard isOwnProfile else { return }
        likedLoading = true
        defer { likedLoading = false }
        await interactions.ensureLoaded()
        let hashes = Array(interactions.likedHashes)
        guard !hashes.isEmpty else {
            likedTweets = []
            likedLoaded = true
            return
        }
        let resolved = await withTaskGroup(of: Tweet?.self) { group in
            for hash in hashes {
                group.addTask { [api = app.api] in
                    try? await api.fetchTweet(hash: hash)
                }
            }
            var collected: [Tweet] = []
            for await t in group {
                if let t { collected.append(t) }
            }
            return collected
        }
        likedTweets = resolved.sorted { $0.timestamp > $1.timestamp }
        likedLoaded = true
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
