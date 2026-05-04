import SwiftUI

struct TweetCardView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var interactions: InteractionCache
    let tweet: Tweet
    var onReplyTap: (() -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    @State private var pendingAction = false
    @State private var error: String?
    @State private var presentingReply = false

    /// Read directly from the shared InteractionCache so paginated
    /// feeds, the search results, the bookmarks tab, and the profile
    /// timeline all reflect the same live state without each view
    /// owning its own copy.
    private var liked: Bool { interactions.contains(liked: tweet.hash) }
    private var bookmarked: Bool { interactions.contains(bookmarked: tweet.hash) }
    private var retweeted: Bool { interactions.contains(retweeted: tweet.hash) }

    /// Label for the "X retweeted" header that profile feeds surface
    /// when a row is somebody else's tweet that the profile owner
    /// retweeted. Nil for organic tweets so the header collapses.
    private var retweeterLabel: String? {
        if let u = tweet.retweetedByUsername { return "\(u).tribe" }
        if let t = tweet.retweetedByTid { return "TID #\(t)" }
        return nil
    }

    private var displayName: String {
        if let u = tweet.username { return "\(u).tribe" }
        return "TID #\(tweet.tid)"
    }

    private var initial: String {
        if let u = tweet.username, let first = u.first { return String(first).uppercased() }
        return String(tweet.tid.prefix(1))
    }

    private var isOwnTweet: Bool {
        guard let myTID = app.myTID else { return false }
        return tweet.tid == myTID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let retweeterLabel {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.caption)
                    Text("\(retweeterLabel) retweeted")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 10) {
                authorChip
                Spacer()
                if isOwnTweet {
                    Menu {
                        Button(role: .destructive) {
                            Task { await deleteTweet() }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                } else if let channel = tweet.channelId {
                    Text("#\(channel)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(TribeColor.chipBackground))
                }
            }

            if let text = tweet.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let imageURLs = embedImageURLs(), !imageURLs.isEmpty {
                embedGrid(imageURLs)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            actionRow
        }
        .padding(.vertical, 6)
        .task {
            await interactions.ensureLoaded()
        }
        .sheet(isPresented: $presentingReply) {
            ComposeTweetView(parentHash: tweet.hash)
                .presentationDetents([.medium, .large])
                .environmentObject(app)
                .environmentObject(interactions)
        }
    }

    /// Avatar + display name + meta line. Wrapped in a NavigationLink
    /// when the row belongs to somebody else so tapping it pushes
    /// their profile; rendered as plain text on own-tweets to avoid
    /// a self-pushing nav cycle that just duplicates the Profile tab.
    @ViewBuilder
    private var authorChip: some View {
        let stack = HStack(alignment: .center, spacing: 10) {
            AvatarView(initial: initial)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(RelativeTime.short(tweet.timestamp)) · TID #\(tweet.tid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())

        if isOwnTweet {
            stack
        } else {
            NavigationLink {
                ProfileView(tid: tweet.tid)
            } label: {
                stack
            }
            .buttonStyle(.plain)
        }
    }

    private func embedImageURLs() -> [URL]? {
        let resolved = (tweet.embeds ?? []).compactMap { app.api.resolveMediaURL($0) }
        return resolved.isEmpty ? nil : resolved
    }

    @ViewBuilder
    private func embedGrid(_ urls: [URL]) -> some View {
        let columns: [GridItem] = urls.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(urls, id: \.self) { url in
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Color(.tertiarySystemFill)
                    default:
                        Color(.tertiarySystemFill)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: urls.count == 1 ? 240 : 140)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 28) {
            actionButton(symbol: "bubble.left", count: tweet.replyCount, active: false) {
                presentingReply = true
            }
            actionButton(
                symbol: "arrow.2.squarepath",
                count: nil,
                active: retweeted,
                activeTint: Color(red: 0.16, green: 0.65, blue: 0.42)
            ) {
                Task { await toggleRetweet() }
            }
            actionButton(
                symbol: liked ? "heart.fill" : "heart",
                count: nil,
                active: liked,
                activeTint: .pink
            ) {
                Task { await toggleLike() }
            }
            actionButton(
                symbol: bookmarked ? "bookmark.fill" : "bookmark",
                count: nil,
                active: bookmarked,
                activeTint: .blue
            ) {
                Task { await toggleBookmark() }
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    private func actionButton(
        symbol: String,
        count: Int?,
        active: Bool,
        activeTint: Color = .accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.subheadline)
                if let n = count, n > 0 {
                    Text("\(n)").font(.caption)
                }
            }
            .foregroundStyle(active ? activeTint : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pendingAction || app.appKey == nil || app.myTID == nil)
    }

    // MARK: - Actions

    private func toggleLike() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        let wasLiked = liked
        interactions.setLiked(!wasLiked, hash: tweet.hash)
        pendingAction = true
        defer { pendingAction = false }
        do {
            if wasLiked {
                try await app.api.unlikeTweet(hash: tweet.hash, as: key, tid: tid)
            } else {
                try await app.api.likeTweet(hash: tweet.hash, as: key, tid: tid)
            }
            error = nil
        } catch {
            interactions.setLiked(wasLiked, hash: tweet.hash)
            self.error = "Like failed: \(error.localizedDescription)"
        }
    }

    private func toggleRetweet() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        let wasRetweeted = retweeted
        interactions.setRetweeted(!wasRetweeted, hash: tweet.hash)
        pendingAction = true
        defer { pendingAction = false }
        do {
            if wasRetweeted {
                try await app.api.unretweet(hash: tweet.hash, as: key, tid: tid)
            } else {
                try await app.api.retweet(hash: tweet.hash, as: key, tid: tid)
            }
            error = nil
        } catch {
            interactions.setRetweeted(wasRetweeted, hash: tweet.hash)
            self.error = "Retweet failed: \(error.localizedDescription)"
        }
    }

    private func toggleBookmark() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        let wasBookmarked = bookmarked
        interactions.setBookmarked(!wasBookmarked, hash: tweet.hash)
        pendingAction = true
        defer { pendingAction = false }
        do {
            try await app.api.bookmark(hash: tweet.hash, as: key, tid: tid, add: !wasBookmarked)
            error = nil
        } catch {
            interactions.setBookmarked(wasBookmarked, hash: tweet.hash)
            self.error = "Bookmark failed: \(error.localizedDescription)"
        }
    }

    private func deleteTweet() async {
        guard let key = app.appKey, let tid = app.myTID, isOwnTweet else { return }
        pendingAction = true
        defer { pendingAction = false }
        do {
            try await app.api.deleteTweet(hash: tweet.hash, as: key, tid: tid)
            onDeleted?()
        } catch {
            self.error = "Delete failed: \(error.localizedDescription)"
        }
    }
}
