import Foundation

/// One row from `/v1/feed` / `/v1/tweets/:tid` / `/v1/feed/channel/:id`.
///
/// `retweetedByTid` / `retweetedByUsername` / `retweetedAt` are only
/// populated by `/v1/feed/:tid` (per-user profile feed), where the
/// hub UNIONs the user's own tweets with tweets they've retweeted.
/// Other endpoints leave them nil.
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
    public let retweetedByTid: String?
    public let retweetedByUsername: String?
    public let retweetedAt: Date?

    public var id: String {
        // Profile feeds may surface the same hash twice (the user's
        // own tweet + a separate row when somebody retweets it). Fold
        // the retweeter into the SwiftUI identity so each row is
        // distinct in a List / ForEach.
        if let r = retweetedByTid { return "\(hash)-rt-\(r)" }
        return hash
    }

    enum CodingKeys: String, CodingKey {
        case hash, tid, text, embeds, username, timestamp
        case parentHash = "parent_hash"
        case channelId = "channel_id"
        case replyCount = "reply_count"
        case retweetedByTid = "retweeted_by_tid"
        case retweetedByUsername = "retweeted_by_username"
        case retweetedAt = "retweeted_at"
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
        self.retweetedByTid = try HubDecode.bigIntIfPresent(c, forKey: .retweetedByTid)
        self.retweetedByUsername = try c.decodeIfPresent(String.self, forKey: .retweetedByUsername)
        self.retweetedAt = try HubDecode.dateIfPresent(c, forKey: .retweetedAt)
    }

    /// Memberwise init for synthesizing a Tweet from rows that don't
    /// arrive as a plain `/v1/tweet` payload (e.g. the bookmarks join
    /// returns `target_hash` + `author_tid` instead of `hash` + `tid`).
    public init(
        hash: String,
        tid: String,
        text: String?,
        parentHash: String?,
        channelId: String?,
        embeds: [String]?,
        timestamp: Date,
        username: String?,
        replyCount: Int?,
        retweetedByTid: String? = nil,
        retweetedByUsername: String? = nil,
        retweetedAt: Date? = nil
    ) {
        self.hash = hash
        self.tid = tid
        self.text = text
        self.parentHash = parentHash
        self.channelId = channelId
        self.embeds = embeds
        self.timestamp = timestamp
        self.username = username
        self.replyCount = replyCount
        self.retweetedByTid = retweetedByTid
        self.retweetedByUsername = retweetedByUsername
        self.retweetedAt = retweetedAt
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

/// Paginated feed reply. The hub returns `cursor` only when it
/// served a full page; nil means there's nothing past this point.
/// Carry the cursor along on the next fetch as `?cursor=…` to walk
/// backward in time.
public struct FeedPage: Decodable {
    public let tweets: [Tweet]
    public let cursor: String?
}
