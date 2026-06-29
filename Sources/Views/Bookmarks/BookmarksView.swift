import SwiftUI

/// Mirror of tribe-twitter-app's /bookmarks page. Lists every tweet the user
/// has bookmarked, most-recently-saved first. Hub joins each bookmark
/// row against the messages table on the way out so we get the full
/// tweet body in a single round-trip.
struct BookmarksView: View {
    @EnvironmentObject private var app: AppState
    @State private var tweets: [Tweet] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if app.myTID == nil {
                EmptyStateView(
                    symbol: "person.crop.circle.badge.exclamationmark",
                    title: "Sign in required",
                    message: "Set your TID in Settings to see tweets you've bookmarked."
                )
            } else if loading && tweets.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in BookmarkSkeletonRow() }
                    }
                    .padding(.vertical, 8)
                }
            } else if let error {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load bookmarks",
                    message: error,
                    action: ("Retry", load)
                )
            } else if tweets.isEmpty {
                EmptyStateView(
                    symbol: "bookmark",
                    title: "No bookmarks yet",
                    message: "Tap the bookmark icon on any tweet to save it here."
                )
            } else {
                List {
                    ForEach(tweets) { tweet in
                        TweetCardView(tweet: tweet, onDeleted: {
                            // If the bookmarked tweet itself is deleted,
                            // drop it from the list rather than waiting
                            // for the next refresh.
                            tweets.removeAll { $0.hash == tweet.hash }
                        })
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(TribeColor.pageBackground)
        .navigationTitle("Bookmarks")
        .refreshable { await refresh() }
        .task { load() }
    }

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard let tid = app.myTID else { loading = false; return }
        loading = tweets.isEmpty
        error = nil
        do {
            tweets = try await app.api.fetchBookmarkedTweets(tid: tid)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct BookmarkSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(TribeColor.chipBackground).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 180, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(maxWidth: .infinity).frame(height: 10)
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 220, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
    }
}
