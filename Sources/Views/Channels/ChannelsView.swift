import SwiftUI

struct ChannelsView: View {
    @EnvironmentObject private var app: AppState
    @State private var channels: [Channel] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if loading {
                    ForEach(0..<5, id: \.self) { _ in ChannelSkeleton() }
                } else if let error {
                    EmptyStateView(
                        symbol: "wifi.exclamationmark",
                        title: "Couldn't load channels",
                        message: error,
                        action: ("Retry", load)
                    )
                    .padding(.horizontal, 16)
                } else if channels.isEmpty {
                    EmptyStateView(
                        symbol: "number",
                        title: "No channels yet",
                        message: "Channels are topic-based feeds. Create one from tribe-app or post a tweet with a channel."
                    )
                    .padding(.horizontal, 16)
                } else {
                    ForEach(channels) { ch in
                        ChannelRow(channel: ch)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
        .background(TribeColor.pageBackground)
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
        Card(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(TribeColor.chipBackground)
                    Text("#")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(TribeColor.textPrimary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(channel.displayName)
                            .font(.system(size: 15, weight: .bold))
                        if channel.kind == 2 {
                            Pill(text: "city", color: TribeColor.accentEmerald)
                        }
                    }
                    Text(channel.description ?? "#\(channel.id)")
                        .font(.system(size: 12))
                        .foregroundStyle(TribeColor.textSecondary)
                        .lineLimit(1)
                    Text("\(channel.memberCount) members · \(channel.tweetCount) tweets")
                        .font(.system(size: 11))
                        .foregroundStyle(TribeColor.textTertiary)
                }
                Spacer()
            }
        }
    }
}

struct Pill: View {
    let text: String
    var color: Color = TribeColor.textSecondary
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

private struct ChannelSkeleton: View {
    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14).fill(TribeColor.chipBackground).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 120, height: 11)
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 200, height: 9)
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 90, height: 9)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }
}
