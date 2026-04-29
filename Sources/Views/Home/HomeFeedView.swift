import SwiftUI

struct HomeFeedView: View {
    @EnvironmentObject private var app: AppState
    @State private var tweets: [Tweet] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader("Home", subtitle: "Tweets across the network")

                LazyVStack(spacing: 12) {
                    if loading {
                        ForEach(0..<3, id: \.self) { _ in TweetSkeleton() }
                    } else if let error {
                        EmptyStateView(
                            symbol: "wifi.exclamationmark",
                            title: "Couldn't load feed",
                            body: error,
                            action: ("Retry", load)
                        )
                        .padding(.horizontal, 16)
                    } else if tweets.isEmpty {
                        EmptyStateView(
                            symbol: "sparkles",
                            title: "It's quiet here",
                            body: "Once people start posting, their tweets will appear here in real time."
                        )
                        .padding(.horizontal, 16)
                    } else {
                        ForEach(tweets) { tweet in
                            TweetCardView(tweet: tweet)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: TribeMetrics.bottomNavReservedHeight)
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
        loading = tweets.isEmpty
        error = nil
        do {
            tweets = try await app.api.fetchFeed()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct TweetSkeleton: View {
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(TribeColor.chipBackground).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(TribeColor.chipBackground).frame(width: 120, height: 12)
                    RoundedRectangle(cornerRadius: 6).fill(TribeColor.chipBackground).frame(maxWidth: .infinity).frame(height: 12)
                    RoundedRectangle(cornerRadius: 6).fill(TribeColor.chipBackground).frame(width: 200, height: 12)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}
