import Foundation

/// One row from `/v1/channels` (or `/v1/users/:tid/channels` for joined).
/// Hub returns id (the slug), not channel_id.
public struct Channel: Decodable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let description: String?
    public let kind: Int?
    public let tweetCount: Int
    public let memberCount: Int
    public let lastTweetAt: Date?

    public var displayName: String {
        if let n = name, !n.isEmpty { return n }
        return "#\(id)"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, kind
        case tweetCount = "tweet_count"
        case memberCount = "member_count"
        case lastTweetAt = "last_tweet_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.kind = try c.decodeIfPresent(Int.self, forKey: .kind)
        self.tweetCount = HubDecode.intCount(c, forKey: .tweetCount)
        self.memberCount = HubDecode.intCount(c, forKey: .memberCount)
        self.lastTweetAt = try HubDecode.dateIfPresent(c, forKey: .lastTweetAt)
    }
}

public struct ChannelListResponse: Decodable {
    public let channels: [Channel]
}
