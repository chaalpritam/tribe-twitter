import SwiftUI

/// Twitter-style tweet detail. Optional parent thread context above,
/// the focused tweet expanded in larger type with a full timestamp,
/// the action row, and replies as standard tweet rows underneath.
/// A sticky "Tweet your reply" bar at the bottom presents the
/// composer with the parent hash already set.
struct TweetDetailView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var interactions: InteractionCache
    @EnvironmentObject private var tipStats: OnchainTipStatsCache

    let tweet: Tweet

    @State private var parent: Tweet?
    @State private var replies: [Tweet] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selectedTweet: Tweet?
    @State private var presentingReply = false
    @State private var presentingTip = false

    private var liked: Bool { interactions.contains(liked: tweet.hash) }
    private var bookmarked: Bool { interactions.contains(bookmarked: tweet.hash) }
    private var retweeted: Bool { interactions.contains(retweeted: tweet.hash) }

    private var displayName: String {
        if let u = tweet.username { return u }
        return "TID #\(tweet.tid)"
    }

    private var handle: String {
        if let u = tweet.username { return "@\(u).tribe" }
        return "@tid\(tweet.tid)"
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
        List {
            if let parent {
                replyContextRow(parent: parent)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            expandedTweet
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            if loading && replies.isEmpty {
                ForEach(0..<2, id: \.self) { _ in
                    ReplySkeleton()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            } else if let error, replies.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(TribeColor.accentRose)
                    .font(.footnote)
                    .padding(16)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            } else if !replies.isEmpty {
                ForEach(replies) { reply in
                    TweetCardView(tweet: reply)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTweet = reply }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            } else {
                Text("No replies yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Tweet")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedTweet) { t in
            TweetDetailView(tweet: t)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            replyBar
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $presentingReply) {
            ComposeTweetView(parentHash: tweet.hash, onPublished: { _ in
                Task { await refresh() }
            })
            .presentationDetents([.medium, .large])
            .environmentObject(app)
            .environmentObject(interactions)
        }
        .sheet(isPresented: $presentingTip) {
            TipSheet(
                recipientTid: tweet.tid,
                recipientName: displayName,
                tweetHash: tweet.hash
            )
            .presentationDetents([.medium])
            .environmentObject(app)
        }
    }

    // MARK: - Parent context row

    /// Small "Replying to @parent" header with a thin connector line
    /// down to the focused tweet, then the parent rendered as a
    /// standard tweet row that pushes its own detail on tap.
    private func replyContextRow(parent: Tweet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TweetCardView(tweet: parent)
                .contentShape(Rectangle())
                .onTapGesture { selectedTweet = parent }
        }
    }

    // MARK: - Expanded focused tweet

    private var expandedTweet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                UserAvatar(
                    tid: tweet.tid,
                    initial: initial,
                    size: 48,
                    seed: tweet.username ?? tweet.tid
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text(handle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                } else if let channel = tweet.channelId {
                    Text("#\(channel)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TribeColor.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(TribeColor.brand.opacity(0.12)))
                }
            }

            if let text = tweet.text, !text.isEmpty {
                Text(text)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }

            if let imageURLs = embedImageURLs(), !imageURLs.isEmpty {
                embedGrid(imageURLs)
            }

            // Full timestamp ("10:24 AM · Apr 12, 2026") with the
            // optional reply count rolled in if the hub returned one.
            HStack(spacing: 4) {
                Text(timestampLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let n = tweet.replyCount, n > 0 {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(n) repl\(n == 1 ? "y" : "ies")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let stats = tipStats.stats(for: tweet.hash), stats.tipCount > 0 {
                tipRollupRow(stats)
            }

            Divider()

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(TribeColor.accentRose)
            }

            actionRow
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TribeColor.cardStroke.opacity(0.4))
                .frame(height: 0.5)
        }
        .task {
            await interactions.ensureLoaded()
            tipStats.ensureLoaded(hash: tweet.hash)
        }
    }

    private var timestampLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a · MMM d, yyyy"
        return formatter.string(from: tweet.timestamp)
    }

    private func tipRollupRow(_ stats: OnchainTipStats) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.subheadline)
                .foregroundStyle(TribeColor.accentAmber)
            Text("\(stats.tipCount) tip\(stats.tipCount == 1 ? "" : "s") · \(stats.formattedSol) SOL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TribeColor.accentAmber)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(TribeColor.accentAmber.opacity(0.12)))
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
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(urls, id: \.self) { url in
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color(.tertiarySystemFill)
                }
                .frame(maxWidth: .infinity)
                .frame(height: urls.count == 1 ? 280 : 160)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionButton(
                symbol: "bubble.left",
                count: tweet.replyCount,
                active: false,
                activeTint: TribeColor.brand
            ) { presentingReply = true }

            Spacer(minLength: 0)

            actionButton(
                symbol: "arrow.2.squarepath",
                count: nil,
                active: retweeted,
                activeTint: TribeColor.accentEmerald
            ) { Task { await toggleRetweet() } }

            Spacer(minLength: 0)

            actionButton(
                symbol: liked ? "heart.fill" : "heart",
                count: nil,
                active: liked,
                activeTint: TribeColor.accentRose
            ) { Task { await toggleLike() } }

            Spacer(minLength: 0)

            actionButton(
                symbol: bookmarked ? "bookmark.fill" : "bookmark",
                count: nil,
                active: bookmarked,
                activeTint: TribeColor.accentIndigo
            ) { Task { await toggleBookmark() } }

            Spacer(minLength: 0)

            if !isOwnTweet {
                Button {
                    presentingTip = true
                } label: {
                    Image(systemName: "dollarsign.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(app.appKey == nil || app.myTID == nil)
            } else {
                Color.clear.frame(width: 24, height: 1)
            }

            Spacer(minLength: 0)

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
        }
    }

    private var shareText: String {
        var lines: [String] = []
        if let text = tweet.text, !text.isEmpty { lines.append(text) }
        lines.append("— \(displayName) (\(handle))")
        return lines.joined(separator: "\n")
    }

    private func actionButton(
        symbol: String,
        count: Int?,
        active: Bool,
        activeTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.body.weight(active ? .semibold : .regular))
                if let n = count, n > 0 {
                    Text("\(n)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(active ? activeTint : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(app.appKey == nil || app.myTID == nil)
    }

    // MARK: - Sticky reply bar

    private var replyBar: some View {
        HStack(spacing: 12) {
            if let myTID = app.myTID {
                UserAvatar(
                    tid: myTID,
                    initial: String((app.myUsername ?? myTID).prefix(1)).uppercased(),
                    size: 32,
                    seed: app.myUsername ?? myTID
                )
            }
            Button {
                presentingReply = true
            } label: {
                HStack {
                    Text("Tweet your reply")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.subheadline)
                        .foregroundStyle(TribeColor.brand)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(Color(.tertiarySystemFill))
                )
            }
            .buttonStyle(.plain)
            .disabled(app.appKey == nil || app.myTID == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TribeColor.cardStroke.opacity(0.4))
                .frame(height: 0.5)
        }
    }

    // MARK: - Data loading

    @MainActor
    private func refresh() async {
        loading = replies.isEmpty
        defer { loading = false }
        async let repliesTask = app.api.fetchReplies(hash: tweet.hash)
        async let parentTask: Tweet? = {
            guard let parentHash = tweet.parentHash else { return nil }
            return try? await app.api.fetchTweet(hash: parentHash)
        }()
        do {
            replies = try await repliesTask
            parent = await parentTask
            error = nil
        } catch {
            self.error = error.localizedDescription
            parent = await parentTask
        }
    }

    // MARK: - Actions

    @MainActor
    private func toggleLike() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        let wasLiked = liked
        interactions.setLiked(!wasLiked, hash: tweet.hash)
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

    @MainActor
    private func toggleRetweet() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        let wasRetweeted = retweeted
        interactions.setRetweeted(!wasRetweeted, hash: tweet.hash)
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

    @MainActor
    private func toggleBookmark() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        let wasBookmarked = bookmarked
        interactions.setBookmarked(!wasBookmarked, hash: tweet.hash)
        do {
            try await app.api.bookmark(hash: tweet.hash, as: key, tid: tid, add: !wasBookmarked)
            error = nil
        } catch {
            interactions.setBookmarked(wasBookmarked, hash: tweet.hash)
            self.error = "Bookmark failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteTweet() async {
        guard let key = app.appKey, let tid = app.myTID, isOwnTweet else { return }
        do {
            try await app.api.deleteTweet(hash: tweet.hash, as: key, tid: tid)
            // Pop back so the user doesn't keep staring at a tweet
            // that no longer exists. The parent feed will refresh on
            // next .task.
            // (No explicit dismiss API on plain NavigationStack push
            // without a binding — leave the user where they are; the
            // toolbar back button still works.)
        } catch {
            self.error = "Delete failed: \(error.localizedDescription)"
        }
    }
}

private struct ReplySkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color(.tertiarySystemFill)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 140, height: 11)
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
