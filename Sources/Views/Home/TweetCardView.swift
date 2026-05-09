import SwiftUI

/// Twitter-style tweet row. Avatar is pinned to the leading edge,
/// header (name + handle + time) and body share the trailing column,
/// and the action row sits directly under the body. Rows render
/// edge-to-edge with a hairline separator at the bottom; List should
/// hide its own separators and use zero row insets so this view
/// owns the full row chrome.
struct TweetCardView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var interactions: InteractionCache
    @EnvironmentObject private var tipStats: OnchainTipStatsCache
    let tweet: Tweet
    var onReplyTap: (() -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    @State private var pendingAction = false
    @State private var error: String?
    @State private var presentingReply = false
    @State private var presentingTip = false

    private var liked: Bool { interactions.contains(liked: tweet.hash) }
    private var bookmarked: Bool { interactions.contains(bookmarked: tweet.hash) }
    private var retweeted: Bool { interactions.contains(retweeted: tweet.hash) }

    private var retweeterLabel: String? {
        if let u = tweet.retweetedByUsername { return "\(u).tribe" }
        if let t = tweet.retweetedByTid { return "TID #\(t)" }
        return nil
    }

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
        VStack(alignment: .leading, spacing: 4) {
            if let retweeterLabel {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.caption2.weight(.semibold))
                    Text("\(retweeterLabel) retweeted")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 56)
            }

            HStack(alignment: .top, spacing: 12) {
                UserAvatar(
                    tid: tweet.tid,
                    initial: initial,
                    size: 44,
                    seed: tweet.username ?? tweet.tid
                )

                VStack(alignment: .leading, spacing: 4) {
                    headerRow
                    if let text = tweet.text, !text.isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                    if let imageURLs = embedImageURLs(), !imageURLs.isEmpty {
                        embedGrid(imageURLs)
                            .padding(.top, 4)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(TribeColor.accentRose)
                    }
                    actionRow
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .task {
            await interactions.ensureLoaded()
            tipStats.ensureLoaded(hash: tweet.hash)
        }
        .sheet(isPresented: $presentingReply) {
            ComposeTweetView(parentHash: tweet.hash)
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

    private var headerRow: some View {
        HStack(spacing: 4) {
            Text(displayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Text(handle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("·")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Text(RelativeTime.short(tweet.timestamp))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if isOwnTweet {
                Menu {
                    Button(role: .destructive) {
                        Task { await deleteTweet() }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
            } else if let channel = tweet.channelId {
                Text("#\(channel)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TribeColor.brand)
            }
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
        LazyVGrid(columns: columns, spacing: 4) {
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
                .frame(height: urls.count == 1 ? 220 : 140)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

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

            trailingActionSlot
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var trailingActionSlot: some View {
        if !isOwnTweet {
            tipActionButton
        } else if let stats = tipStats.stats(for: tweet.hash), stats.tipCount > 0 {
            tipReceivedChip(stats)
        } else {
            // Empty placeholder so other-tweet rows and own-tweet rows
            // share the same trailing column anchor — keeps the four
            // standard buttons spaced identically across both cases.
            Color.clear.frame(width: 24, height: 1)
        }
    }

    @ViewBuilder
    private var tipActionButton: some View {
        let stats = tipStats.stats(for: tweet.hash)
        let hasTips = (stats?.tipCount ?? 0) > 0
        Button {
            presentingTip = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasTips ? "dollarsign.circle.fill" : "dollarsign.circle")
                    .font(.subheadline)
                if let stats, stats.tipCount > 0 {
                    Text("\(stats.tipCount)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(hasTips ? TribeColor.accentAmber : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pendingAction || app.appKey == nil || app.myTID == nil)
    }

    private func tipReceivedChip(_ stats: OnchainTipStats) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.subheadline)
            Text("\(stats.tipCount) · \(stats.formattedSol)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(TribeColor.accentAmber)
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
                    .font(.subheadline.weight(active ? .semibold : .regular))
                if let n = count, n > 0 {
                    Text("\(n)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
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
