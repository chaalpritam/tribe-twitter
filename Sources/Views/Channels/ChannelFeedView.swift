import SwiftUI
import TribeCore

/// One-channel feed. Lists tweets from /v1/feed/channel/:id with the
/// usual pull-to-refresh, and a "+" toolbar button that opens a
/// channel-scoped composer.
struct ChannelFeedView: View {
    @EnvironmentObject private var app: AppState
    let channel: Channel

    @State private var tweets: [Tweet] = []
    @State private var loading = true
    @State private var error: String?
    @State private var presentingCompose = false

    var body: some View {
        Group {
            if loading && tweets.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, tweets.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load channel",
                    message: error,
                    action: ("Retry", { Task { await refresh() } })
                )
            } else if tweets.isEmpty {
                EmptyStateView(
                    symbol: "number",
                    title: "Quiet channel",
                    message: "No tweets in #\(channel.id) yet. Tap + to be the first."
                )
            } else {
                List(tweets) { tweet in
                    NavigationLink {
                        TweetDetailView(tweet: tweet)
                    } label: {
                        TweetCardView(tweet: tweet)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(channel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentingCompose = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New post in \(channel.displayName)")
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $presentingCompose) {
            ComposeTweetView(channelId: channel.id, onPublished: { _ in
                Task { await refresh() }
            })
            .presentationDetents([.medium, .large])
            .environmentObject(app)
        }
    }

    @MainActor
    private func refresh() async {
        loading = tweets.isEmpty
        defer { loading = false }
        error = nil
        do {
            tweets = try await app.api.fetchChannelFeed(channel.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
