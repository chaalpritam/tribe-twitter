import SwiftUI

struct HomeFeedView: View {
    @EnvironmentObject private var app: AppState
    @State private var tweets: [Tweet] = []
    @State private var loading = true
    @State private var error: String?
    @State private var presentingCompose = false

    var body: some View {
        Group {
            if loading && tweets.isEmpty {
                List {
                    ForEach(0..<3, id: \.self) { _ in
                        TweetSkeleton()
                    }
                }
                .listStyle(.plain)
            } else if let error, tweets.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load feed",
                    message: error,
                    action: ("Retry", load)
                )
            } else if tweets.isEmpty {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "It's quiet here",
                    message: "Once people start posting, their tweets will appear here in real time."
                )
            } else {
                List(tweets) { tweet in
                    TweetCardView(tweet: tweet)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
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
            ComposeTweetView(onPublished: { _ in
                Task { await refresh() }
            })
            .presentationDetents([.medium, .large])
            .environmentObject(app)
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
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color(.tertiarySystemFill)).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)).frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 12)
                RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)).frame(width: 200, height: 12)
            }
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
    }
}

