import SwiftUI

struct TweetCardView: View {
    @EnvironmentObject private var app: AppState
    let tweet: Tweet
    var onReplyTap: (() -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    @State private var liked = false
    @State private var bookmarked = false
    @State private var pendingAction = false
    @State private var error: String?
    @State private var presentingReply = false

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
            HStack(alignment: .center, spacing: 10) {
                AvatarView(initial: initial)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(RelativeTime.short(tweet.timestamp)) · TID #\(tweet.tid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .sheet(isPresented: $presentingReply) {
            ComposeTweetView(parentHash: tweet.hash)
                .presentationDetents([.medium, .large])
                .environmentObject(app)
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
        liked.toggle()
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
            liked = wasLiked
            self.error = "Like failed: \(error.localizedDescription)"
        }
    }

    private func toggleBookmark() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        let wasBookmarked = bookmarked
        bookmarked.toggle()
        pendingAction = true
        defer { pendingAction = false }
        do {
            try await app.api.bookmark(hash: tweet.hash, as: key, tid: tid, add: !wasBookmarked)
            error = nil
        } catch {
            bookmarked = wasBookmarked
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
