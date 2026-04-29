import Foundation

/// Read-only mirror of every hub endpoint tribe-app's web client uses.
/// Names are deliberately the same as the JS helpers in
/// `tribe-app/src/lib/api.ts` so the two clients can be eyeballed
/// side-by-side.
public extension HubClient {
    // MARK: - Feeds

    func fetchFeed(tid: String? = nil) async throws -> [Tweet] {
        if let tid {
            let res: TweetListResponse = try await get("v1/feed/\(tid)")
            return res.tweets
        }
        let res: TweetListResponse = try await get("v1/feed")
        return res.tweets
    }

    func fetchTweets(tid: String? = nil) async throws -> [Tweet] {
        if let tid {
            let res: TweetListResponse = try await get("v1/tweets/\(tid)")
            return res.tweets
        }
        let res: TweetListResponse = try await get("v1/tweets")
        return res.tweets
    }

    func fetchTweet(hash: String) async throws -> Tweet {
        try await get("v1/tweet/\(hash)")
    }

    func fetchReplies(hash: String) async throws -> [Tweet] {
        struct R: Decodable { let replies: [Tweet] }
        let r: R = try await get("v1/replies", query: ["hash": hash])
        return r.replies
    }

    func fetchChannelFeed(_ channelId: String) async throws -> [Tweet] {
        let res: TweetListResponse = try await get("v1/feed/channel/\(channelId)")
        return res.tweets
    }

    // MARK: - Users

    func fetchUsers(limit: Int = 50) async throws -> [User] {
        let res: UserListResponse = try await get("v1/users", query: ["limit": String(limit)])
        return res.users
    }

    func fetchUser(_ tid: String) async throws -> User {
        try await get("v1/user/\(tid)")
    }

    // MARK: - Channels

    func fetchChannels() async throws -> [Channel] {
        let res: ChannelListResponse = try await get("v1/channels")
        return res.channels
    }

    func fetchJoinedChannels(_ tid: String) async throws -> [Channel] {
        let res: ChannelListResponse = try await get("v1/users/\(tid)/channels")
        return res.channels
    }

    // MARK: - Polls

    func fetchPolls() async throws -> [Poll] {
        let res: PollListResponse = try await get("v1/polls")
        return res.polls
    }

    func fetchPoll(_ id: String) async throws -> PollDetailResponse {
        try await get("v1/polls/\(id)")
    }

    // MARK: - Events

    func fetchEvents(upcomingOnly: Bool = true) async throws -> [Event] {
        let q = upcomingOnly ? ["upcoming": "true"] : [:]
        let res: EventListResponse = try await get("v1/events", query: q)
        return res.events
    }

    // MARK: - Tasks

    func fetchTasks(status: String? = nil) async throws -> [TaskItem] {
        let q = status.map { ["status": $0] } ?? [:]
        let res: TaskListResponse = try await get("v1/tasks", query: q)
        return res.tasks
    }

    // MARK: - Crowdfunds

    func fetchCrowdfunds() async throws -> [Crowdfund] {
        let res: CrowdfundListResponse = try await get("v1/crowdfunds")
        return res.crowdfunds
    }

    // MARK: - Tips

    func fetchTipsSent(_ tid: String, limit: Int = 50) async throws -> [Tip] {
        let res: TipListResponse = try await get(
            "v1/tips/sent/\(tid)",
            query: ["limit": String(limit)]
        )
        return res.tips
    }

    func fetchTipsReceived(_ tid: String, limit: Int = 50) async throws -> [Tip] {
        let res: TipListResponse = try await get(
            "v1/tips/received/\(tid)",
            query: ["limit": String(limit)]
        )
        return res.tips
    }

    // MARK: - Notifications

    func fetchNotifications(_ tid: String, limit: Int = 50) async throws -> [TribeNotification] {
        let res: NotificationListResponse = try await get(
            "v1/notifications/\(tid)",
            query: ["limit": String(limit)]
        )
        return res.notifications
    }

    func fetchUnreadCount(_ tid: String) async throws -> Int {
        let res: NotificationCountResponse = try await get("v1/notifications/\(tid)/count")
        return res.count
    }

    // MARK: - Karma

    func fetchKarma(_ tid: String) async throws -> KarmaSummary? {
        try? await get("v1/users/\(tid)/karma")
    }

    // MARK: - Search

    func searchTweets(_ query: String) async throws -> [Tweet] {
        let res: TweetListResponse = try await get("v1/search", query: ["q": query, "limit": "30"])
        return res.tweets
    }

    func searchUsers(_ query: String) async throws -> [User] {
        let res: UserListResponse = try await get("v1/search/users", query: ["q": query, "limit": "20"])
        return res.users
    }

    func searchChannels(_ query: String) async throws -> [Channel] {
        let res: ChannelListResponse = try await get("v1/search/channels", query: ["q": query, "limit": "20"])
        return res.channels
    }

    func searchPolls(_ query: String) async throws -> [Poll] {
        let res: PollListResponse = try await get("v1/search/polls", query: ["q": query, "limit": "20"])
        return res.polls
    }

    func searchEvents(_ query: String) async throws -> [Event] {
        let res: EventListResponse = try await get("v1/search/events", query: ["q": query, "limit": "20"])
        return res.events
    }

    func searchTasks(_ query: String) async throws -> [TaskItem] {
        let res: TaskListResponse = try await get("v1/search/tasks", query: ["q": query, "limit": "20"])
        return res.tasks
    }

    func searchCrowdfunds(_ query: String) async throws -> [Crowdfund] {
        let res: CrowdfundListResponse = try await get("v1/search/crowdfunds", query: ["q": query, "limit": "20"])
        return res.crowdfunds
    }

    // MARK: - Media URL resolver

    /// `media:<hash>` and absolute `/v1/media/<hash>` references both
    /// route to whichever hub the app is currently pointing at, so
    /// embedded images survive a hub IP change.
    func resolveMediaURL(_ value: String?) -> URL? {
        guard let v = value else { return nil }
        if v.hasPrefix("media:") {
            let hash = String(v.dropFirst("media:".count))
            return baseURL.appendingPathComponent("v1/media/\(hash)")
        }
        if let range = v.range(of: #"/v1/media/[0-9a-fA-F]{64}"#, options: .regularExpression) {
            let path = String(v[range])
            return baseURL.appendingPathComponent(path)
        }
        return URL(string: v)
    }
}
