import Foundation

/// One row from `/v1/feed` / `/v1/tweets/:tid` / `/v1/feed/channel/:id`.
public struct Tweet: Decodable, Identifiable, Hashable {
    public let hash: String
    public let tid: String
    public let text: String?
    public let parentHash: String?
    public let channelId: String?
    public let embeds: [String]?
    public let timestamp: Date
    public let username: String?
    public let replyCount: Int?

    public var id: String { hash }

    enum CodingKeys: String, CodingKey {
        case hash, tid, text, embeds, username, timestamp
        case parentHash = "parent_hash"
        case channelId = "channel_id"
        case replyCount = "reply_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hash = try c.decode(String.self, forKey: .hash)
        self.tid = try HubDecode.bigInt(c, forKey: .tid)
        self.text = try c.decodeIfPresent(String.self, forKey: .text)
        self.parentHash = try c.decodeIfPresent(String.self, forKey: .parentHash)
        self.channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        self.embeds = try c.decodeIfPresent([String].self, forKey: .embeds)
        self.username = try c.decodeIfPresent(String.self, forKey: .username)
        self.replyCount = try c.decodeIfPresent(Int.self, forKey: .replyCount)
        self.timestamp = try HubDecode.date(c, forKey: .timestamp)
    }
}

public extension ISO8601DateFormatter {
    static let tribe: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let tribePlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

public struct TweetListResponse: Decodable {
    public let tweets: [Tweet]
}
