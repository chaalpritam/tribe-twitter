import SwiftUI

struct HomeFeedView: View {
    @EnvironmentObject private var app: AppState
    @State private var tweets: [Tweet] = []
    @State private var loading = true
    @State private var error: String?
    @State private var presentingCompose = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if loading {
                    ForEach(0..<3, id: \.self) { _ in TweetSkeleton() }
                } else if let error {
                    EmptyStateView(
                        symbol: "wifi.exclamationmark",
                        title: "Couldn't load feed",
                        message: error,
                        action: ("Retry", load)
                    )
                    .padding(.top, 60)
                } else if tweets.isEmpty {
                    EmptyStateView(
                        symbol: "sparkles",
                        title: "It's quiet here",
                        message: "Once people start posting, their tweets will appear here in real time."
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(tweets) { tweet in
                        TweetCardView(tweet: tweet)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(TribeColor.pageBackground)
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentingCompose = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Compose")
            }
        }
        .refreshable { await refresh() }
        .task { load() }
        .sheet(isPresented: $presentingCompose) {
            ComposePlaceholderView()
                .presentationDetents([.medium, .large])
        }
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

private struct ComposePlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Compose", systemImage: "square.and.pencil")
            } description: {
                Text("Tweets, polls, events, tasks and crowdfunds. Wiring this up needs the signed-envelope path ported from tribe-app.")
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
