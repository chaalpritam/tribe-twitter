import SwiftUI

/// Single-tweet view: the parent tweet at the top, then its
/// replies in chronological order. Tapping a reply pushes another
/// detail view, so threads expand naturally.
///
/// Read paths only — composing a reply still goes through
/// TweetCardView's reply button (presents ComposeTweetView with the
/// parent_hash set).
struct TweetDetailView: View {
    @EnvironmentObject private var app: AppState
    let tweet: Tweet

    @State private var replies: [Tweet] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            Section {
                TweetCardView(tweet: tweet)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if loading && replies.isEmpty {
                Section("Replies") {
                    ForEach(0..<2, id: \.self) { _ in
                        ReplySkeleton()
                    }
                }
            } else if let error, replies.isEmpty {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.footnote)
                }
            } else if !replies.isEmpty {
                Section("Replies (\(replies.count))") {
                    ForEach(replies) { reply in
                        NavigationLink {
                            TweetDetailView(tweet: reply)
                        } label: {
                            TweetCardView(tweet: reply)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Section {
                    Text("No replies yet.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Tweet")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor
    private func refresh() async {
        loading = replies.isEmpty
        defer { loading = false }
        do {
            replies = try await app.api.fetchReplies(hash: tweet.hash)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ReplySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 140, height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 160, height: 10)
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
    }
}
