import SwiftUI

struct HomeFeedView: View {
    @EnvironmentObject private var app: AppState
    @State private var tweets: [Tweet] = []
    @State private var loading = true
    @State private var error: String?
    @State private var presentingCompose = false
    @State private var presentingNotifications = false
    @State private var unreadCount = 0
    /// Cursor for the next page. Nil before the first load; nil after
    /// the hub tells us we've reached the tail.
    @State private var nextCursor: String?
    @State private var loadingMore = false
    /// True once the hub has served a page with no further cursor —
    /// stops the trailing skeleton row from re-firing the load.
    @State private var reachedEnd = false

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
                List {
                    ForEach(tweets) { tweet in
                        NavigationLink {
                            TweetDetailView(tweet: tweet)
                        } label: {
                            TweetCardView(tweet: tweet)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .onAppear {
                            // Trigger the next page when the
                            // second-to-last visible row appears so
                            // the user rarely hits a hard stop while
                            // scrolling. With <2 rows we fall through
                            // to the last row.
                            let triggerIndex = max(0, tweets.count - 2)
                            if tweet.id == tweets[triggerIndex].id {
                                Task { await loadMore() }
                            }
                        }
                    }

                    if loadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else if reachedEnd && !tweets.isEmpty {
                        Text("End of feed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    presentingNotifications = true
                } label: {
                    Image(systemName: "bell")
                        .overlay(alignment: .topTrailing) {
                            if unreadCount > 0 {
                                Circle()
                                    .fill(Color.pink)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -2)
                            }
                        }
                }
                .accessibilityLabel("Activity")
            }
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
        .task {
            load()
            await refreshUnread()
        }
        .sheet(isPresented: $presentingCompose) {
            ComposeTweetView(onPublished: { _ in
                Task { await refresh() }
            })
            .presentationDetents([.medium, .large])
            .environmentObject(app)
        }
        .sheet(isPresented: $presentingNotifications) {
            NavigationStack {
                NotificationsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { presentingNotifications = false }
                        }
                    }
            }
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
            let page = try await app.api.fetchFeedPage(cursor: nil)
            tweets = page.tweets
            nextCursor = page.cursor
            reachedEnd = page.cursor == nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// Append the next page of tweets to the bottom of the list.
    /// Bails when there's nothing left, when a page is already
    /// in-flight, or when the initial load hasn't completed yet —
    /// the trailing onAppear can fire before refresh() finishes
    /// otherwise.
    @MainActor
    private func loadMore() async {
        guard let cursor = nextCursor,
              !loadingMore,
              !reachedEnd,
              !loading else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await app.api.fetchFeedPage(cursor: cursor)
            // Defensive de-dupe — gossip may have surfaced new tweets
            // overlapping the cursor edge between the first page and
            // this one.
            let existing = Set(tweets.map(\.id))
            let fresh = page.tweets.filter { !existing.contains($0.id) }
            tweets.append(contentsOf: fresh)
            nextCursor = page.cursor
            reachedEnd = page.cursor == nil
        } catch {
            // Silent failure for now — the user can pull-to-refresh
            // to recover. Surfacing an error per-page would need a
            // dedicated banner since we already use `error` for the
            // initial-load empty state.
        }
    }

    @MainActor
    private func refreshUnread() async {
        guard let tid = app.myTID else { return }
        unreadCount = (try? await app.api.fetchUnreadCount(tid)) ?? 0
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

