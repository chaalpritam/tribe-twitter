import Foundation

/// Named TaskItem to avoid colliding with Swift Concurrency's `Task`.
/// Mirrors the `tasks` table on the hub.
public struct TaskItem: Decodable, Identifiable, Hashable {
    public let id: String
    public let creatorTid: String
    public let creatorUsername: String?
    public let title: String
    public let description: String?
    public let rewardText: String?
    public let status: String
    public let claimedByTid: String?
    public let completedByTid: String?
    public let channelId: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case creatorTid = "creator_tid"
        case creatorUsername = "creator_username"
        case rewardText = "reward_text"
        case claimedByTid = "claimed_by_tid"
        case completedByTid = "completed_by_tid"
        case channelId = "channel_id"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.creatorTid = try HubDecode.bigInt(c, forKey: .creatorTid)
        self.creatorUsername = try c.decodeIfPresent(String.self, forKey: .creatorUsername)
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.rewardText = try c.decodeIfPresent(String.self, forKey: .rewardText)
        self.status = try c.decode(String.self, forKey: .status)
        self.claimedByTid = try HubDecode.bigIntIfPresent(c, forKey: .claimedByTid)
        self.completedByTid = try HubDecode.bigIntIfPresent(c, forKey: .completedByTid)
        self.channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        self.createdAt = try HubDecode.date(c, forKey: .createdAt)
    }
}

public struct TaskListResponse: Decodable {
    public let tasks: [TaskItem]
}
