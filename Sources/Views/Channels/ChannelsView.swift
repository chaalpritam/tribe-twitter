import SwiftUI
import TribeCore

struct ChannelsView: View {
    @EnvironmentObject private var app: AppState
    @State private var channels: [Channel] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading && channels.isEmpty {
                List {
                    ForEach(0..<5, id: \.self) { _ in ChannelSkeleton() }
                }
                .listStyle(.insetGrouped)
            } else if let error, channels.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load channels",
                    message: error,
                    action: ("Retry", load)
                )
            } else if channels.isEmpty {
                EmptyStateView(
                    symbol: "number",
                    title: "No channels yet",
                    message: "Channels are topic-based feeds. Create one from tribe-twitter-app or post a tweet with a channel."
                )
            } else {
                List(channels) { channel in
                    NavigationLink {
                        ChannelFeedView(channel: channel)
                    } label: {
                        ChannelRow(channel: channel)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .refreshable { await refresh() }
        .task { load() }
    }

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        loading = channels.isEmpty
        error = nil
        do {
            channels = try await app.api.fetchChannels()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TribeColor.avatarGradient(seed: "channel-\(channel.id)"))
                Text("#")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 1, x: 0, y: 1)
            }
            .frame(width: 44, height: 44)
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(channel.displayName)
                        .font(.subheadline.weight(.semibold))
                    if channel.kind == 2 {
                        Pill(text: "city", color: TribeColor.accentEmerald)
                    }
                }
                Text(channel.description ?? "#\(channel.id)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(channel.memberCount) members · \(channel.tweetCount) tweets")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

private struct ChannelSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 120, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 200, height: 9)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 90, height: 9)
            }
            Spacer()
        }
        .redacted(reason: .placeholder)
    }
}
