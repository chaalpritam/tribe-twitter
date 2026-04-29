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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader("Search")

                searchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                if debouncedQuery.count < 2 {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "Search Tribe",
                        message: "People, tweets, channels, polls, events, tasks and crowdfunds — all in one place."
                    )
                    .padding(.horizontal, 16)
                } else if loading {
                    ProgressView()
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                } else if totalCount == 0 {
                    EmptyStateView(symbol: "tray", title: "No results", message: "Nothing matched \"\(debouncedQuery)\".")
                        .padding(.horizontal, 16)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !users.isEmpty {
                            section(title: "People (\(users.count))") {
                                ForEach(users) { u in MiniUserRow(user: u) }
                            }
                        }
                        if !channels.isEmpty {
                            section(title: "Channels (\(channels.count))") {
                                ForEach(channels) { c in MiniRow(title: c.displayName, subtitle: "\(c.memberCount) members") }
                            }
                        }
                        if !polls.isEmpty {
                            section(title: "Polls (\(polls.count))") {
                                ForEach(polls) { p in MiniRow(title: p.question, subtitle: "\(p.totalVotes ?? 0) votes · TID #\(p.creatorTid)") }
                            }
                        }
                        if !events.isEmpty {
                            section(title: "Events (\(events.count))") {
                                ForEach(events) { e in MiniRow(title: e.title, subtitle: e.locationText ?? "") }
                            }
                        }
                        if !tasks.isEmpty {
                            section(title: "Tasks (\(tasks.count))") {
                                ForEach(tasks) { t in MiniRow(title: t.title, subtitle: "\(t.status) · TID #\(t.creatorTid)") }
                            }
                        }
                        if !crowdfunds.isEmpty {
                            section(title: "Crowdfunds (\(crowdfunds.count))") {
                                ForEach(crowdfunds) { cf in MiniRow(title: cf.title, subtitle: "TID #\(cf.creatorTid)") }
                            }
                        }
                        if !tweets.isEmpty {
                            section(title: "Tweets (\(tweets.count))") {
                                ForEach(tweets) { tw in TweetCardView(tweet: tw) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: TribeMetrics.bottomNavReservedHeight)
            }
        }
        .background(TribeColor.pageBackground)
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TribeColor.textSecondary)
            TextField("People, tweets, channels…", text: $query)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(TribeColor.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(TribeColor.chipBackground)
        )
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

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(TribeColor.textSecondary)
                .textCase(.uppercase)
            VStack(spacing: 8) { content() }
        }
    }
}

private struct MiniUserRow: View {
    let user: User
    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 10) {
                AvatarView(initial: user.initial, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName).font(.system(size: 13, weight: .bold))
                    Text("\(user.followersCount) followers")
                        .font(.system(size: 11))
                        .foregroundStyle(TribeColor.textSecondary)
                }
                Spacer()
            }
        }
    }
}

private struct MiniRow: View {
    let title: String
    let subtitle: String
    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(TribeColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
