import SwiftUI

struct HomeFeedView: View {
    @EnvironmentObject private var app: AppState
    @State private var tweets: [Tweet] = []
    @State private var loading = true
    @State private var error: String?
    @State private var presentingCompose = false
    @State private var presentingNotifications = false
    @State private var unreadCount = 0

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
            tweets = try await app.api.fetchFeed()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
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

