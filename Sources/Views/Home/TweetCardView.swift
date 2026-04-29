import SwiftUI

struct TweetCardView: View {
    @EnvironmentObject private var app: AppState
    let tweet: Tweet

    private var displayName: String {
        if let u = tweet.username { return "\(u).tribe" }
        return "TID #\(tweet.tid)"
    }

    private var initial: String {
        if let u = tweet.username, let first = u.first { return String(first).uppercased() }
        return String(tweet.tid.prefix(1))
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
                if let channel = tweet.channelId {
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

            actionRow
        }
        .padding(.vertical, 6)
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
            actionIcon("bubble.left", count: tweet.replyCount)
            actionIcon("arrow.2.squarepath", count: nil)
            actionIcon("heart", count: nil)
            actionIcon("bookmark", count: nil)
            Spacer()
            actionIcon("dollarsign.circle", count: nil)
        }
        .foregroundStyle(.secondary)
    }

    private func actionIcon(_ symbol: String, count: Int?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.subheadline)
            if let n = count, n > 0 {
                Text("\(n)").font(.caption)
            }
        }
    }
}
