import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    @State private var users: [User] = []
    @State private var channels: [Channel] = []
    @State private var polls: [Poll] = []
    @State private var events: [Event] = []
    @State private var tasks: [TaskItem] = []
    @State private var crowdfunds: [Crowdfund] = []
    @State private var tweets: [Tweet] = []

    @State private var loading = false

    var body: some View {
        Group {
            if debouncedQuery.count < 2 {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "Search Tribe",
                    message: "People, tweets, channels, polls, events, tasks and crowdfunds — all in one place."
                )
            } else if loading {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if totalCount == 0 {
                EmptyStateView(symbol: "tray", title: "No results", message: "Nothing matched \"\(debouncedQuery)\".")
            } else {
                List {
                    if !users.isEmpty {
                        SwiftUI.Section("People") {
                            ForEach(users) { u in
                                NavigationLink {
                                    ProfileView(tid: u.tid)
                                } label: {
                                    MiniUserRow(user: u)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !channels.isEmpty {
                        SwiftUI.Section("Channels") {
                            ForEach(channels) { c in
                                NavigationLink {
                                    ChannelFeedView(channel: c)
                                } label: {
                                    MiniRow(title: c.displayName, subtitle: "\(c.memberCount) members")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !polls.isEmpty {
                        SwiftUI.Section("Polls") {
                            ForEach(polls) { p in
                                MiniRow(title: p.question, subtitle: "\(p.totalVotes ?? 0) votes · TID #\(p.creatorTid)")
                            }
                        }
                    }
                    if !events.isEmpty {
                        SwiftUI.Section("Events") {
                            ForEach(events) { e in
                                MiniRow(title: e.title, subtitle: e.locationText ?? "")
                            }
                        }
                    }
                    if !tasks.isEmpty {
                        SwiftUI.Section("Tasks") {
                            ForEach(tasks) { t in
                                MiniRow(title: t.title, subtitle: "\(t.status) · TID #\(t.creatorTid)")
                            }
                        }
                    }
                    if !crowdfunds.isEmpty {
                        SwiftUI.Section("Crowdfunds") {
                            ForEach(crowdfunds) { cf in
                                MiniRow(title: cf.title, subtitle: "TID #\(cf.creatorTid)")
                            }
                        }
                    }
                    if !tweets.isEmpty {
                        SwiftUI.Section("Tweets") {
                            ForEach(tweets) { tw in
                                TweetCardView(tweet: tw)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "People, tweets, channels…")
        .textInputAutocapitalization(.never)
        .onChange(of: query) { _, new in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                await MainActor.run { debouncedQuery = new.trimmingCharacters(in: .whitespaces) }
            }
        }
        .onChange(of: debouncedQuery) { _, _ in runSearch() }
    }

    private var totalCount: Int {
        users.count + channels.count + polls.count + events.count + tasks.count + crowdfunds.count + tweets.count
    }

    private func runSearch() {
        guard debouncedQuery.count >= 2 else {
            users = []; channels = []; polls = []; events = []
            tasks = []; crowdfunds = []; tweets = []
            return
        }
        let q = debouncedQuery
        Task {
            await MainActor.run { loading = true }
            async let u = (try? await app.api.searchUsers(q)) ?? []
            async let c = (try? await app.api.searchChannels(q)) ?? []
            async let p = (try? await app.api.searchPolls(q)) ?? []
            async let e = (try? await app.api.searchEvents(q)) ?? []
            async let t = (try? await app.api.searchTasks(q)) ?? []
            async let cf = (try? await app.api.searchCrowdfunds(q)) ?? []
            async let tw = (try? await app.api.searchTweets(q)) ?? []
            let (uu, cc, pp, ee, tt, ccff, ttww) = await (u, c, p, e, t, cf, tw)
            await MainActor.run {
                users = uu; channels = cc; polls = pp; events = ee
                tasks = tt; crowdfunds = ccff; tweets = ttww
                loading = false
            }
        }
    }
}

private struct MiniUserRow: View {
    let user: User
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initial: user.initial, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(user.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(user.followersCount) followers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

private struct MiniRow: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
