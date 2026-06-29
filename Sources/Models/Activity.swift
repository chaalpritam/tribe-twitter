import Foundation

/// User-account transparency log row from `/v1/users/:tid/activity`.
/// Mirrors the web ActivityRow in tribe-twitter-app/src/lib/api.ts so the two
/// surfaces stay 1:1.
public struct ActivityRow: Decodable, Identifiable, Hashable {
    public let type: ActivityType
    /// ISO 8601 timestamp; the hub returns these newest-first.
    public let timestamp: Date
    /// Solana tx signature when the underlying action settled on-chain.
    public let txSignature: String?
    /// Short human-readable snippet — tweet text, tip amount, etc.
    public let preview: String?
    /// Hash of the related message (tweet / dm / bookmark target).
    public let targetHash: String?
    /// Other party's TID for two-party actions (follows, dms, tips).
    public let peerTid: String?

    /// SwiftUI identity. Same composite key the web page uses so the
    /// row stays stable across refreshes.
    public var id: String {
        "\(type.rawValue):\(targetHash ?? peerTid ?? ""):\(timestamp.timeIntervalSince1970)"
    }

    enum CodingKeys: String, CodingKey {
        case type, timestamp, preview
        case txSignature = "tx_signature"
        case targetHash = "target_hash"
        case peerTid = "peer_tid"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Fall back to .unknown rather than failing decode if the hub
        // ever ships a new ActivityType the iOS build hasn't been
        // updated to recognize — better to surface the timestamp + a
        // generic verb than to drop the row.
        let raw = try c.decode(String.self, forKey: .type)
        self.type = ActivityType(rawValue: raw) ?? .unknown
        self.timestamp = try HubDecode.date(c, forKey: .timestamp)
        self.txSignature = try c.decodeIfPresent(String.self, forKey: .txSignature)
        self.preview = try c.decodeIfPresent(String.self, forKey: .preview)
        self.targetHash = try c.decodeIfPresent(String.self, forKey: .targetHash)
        self.peerTid = try HubDecode.bigIntIfPresent(c, forKey: .peerTid)
    }
}

public enum ActivityType: String, Codable, Hashable {
    case tidRegistered = "tid_registered"
    case tweet
    case tweetReply = "tweet_reply"
    case reactionLike = "reaction_like"
    case reactionRecast = "reaction_recast"
    case bookmark
    case dmSent = "dm_sent"
    case tipSent = "tip_sent"
    case tipReceived = "tip_received"
    case followPending = "follow_pending"
    case followSettled = "follow_settled"
    case followFailed = "follow_failed"
    case unfollowPending = "unfollow_pending"
    case unfollowSettled = "unfollow_settled"
    case unfollowFailed = "unfollow_failed"
    case unknown

    /// Human-readable verb — what the row says happened. Matches the
    /// VERB map in tribe-twitter-app/src/app/activity/page.tsx.
    public var verb: String {
        switch self {
        case .tidRegistered: return "Registered TID on Solana"
        case .tweet: return "Posted a tweet"
        case .tweetReply: return "Replied to a tweet"
        case .reactionLike: return "Liked a tweet"
        case .reactionRecast: return "Retweeted"
        case .bookmark: return "Bookmarked a tweet"
        case .dmSent: return "Sent a DM"
        case .tipSent: return "Sent a tip"
        case .tipReceived: return "Received a tip"
        case .followPending: return "Follow (settling onchain)"
        case .followSettled: return "Followed (onchain)"
        case .followFailed: return "Follow failed"
        case .unfollowPending: return "Unfollow (settling onchain)"
        case .unfollowSettled: return "Unfollowed (onchain)"
        case .unfollowFailed: return "Unfollow failed"
        case .unknown: return "Activity"
        }
    }

    /// Whether this row represents an on-chain settlement (vs an
    /// off-chain signed envelope). Drives the activity filter chips.
    public var isOnChain: Bool {
        switch self {
        case .tidRegistered,
             .followPending, .followSettled, .followFailed,
             .unfollowPending, .unfollowSettled, .unfollowFailed,
             .tipSent, .tipReceived:
            return true
        default:
            return false
        }
    }
}
