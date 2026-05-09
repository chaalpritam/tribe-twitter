import Foundation

public enum NotificationType: String, Decodable, CaseIterable {
    case follow
    case reaction
    case reply
    case tip
    case mention
    case pollVote = "poll_vote"
    case eventRsvp = "event_rsvp"
    case taskClaim = "task_claim"
    case taskComplete = "task_complete"
    case crowdfundPledge = "crowdfund_pledge"

    public var label: String {
        switch self {
        case .follow: return "followed you"
        case .reaction: return "reacted to your tweet"
        case .reply: return "replied to your tweet"
        case .tip: return "tipped you"
        case .mention: return "mentioned you"
        case .pollVote: return "voted on your poll"
        case .eventRsvp: return "RSVPed to your event"
        case .taskClaim: return "claimed your task"
        case .taskComplete: return "completed your task"
        case .crowdfundPledge: return "pledged to your crowdfund"
        }
    }

    public var symbol: String {
        switch self {
        case .follow: return "person.badge.plus"
        case .reaction: return "heart.fill"
        case .reply: return "bubble.left"
        case .tip: return "dollarsign.circle"
        case .mention: return "at"
        case .pollVote: return "chart.bar"
        case .eventRsvp: return "calendar"
        case .taskClaim: return "wrench.and.screwdriver"
        case .taskComplete: return "checkmark.seal"
        case .crowdfundPledge: return "circle.hexagongrid"
        }
    }
}

public struct TribeNotification: Decodable, Hashable, Identifiable {
    public let type: NotificationType
    public let actorTid: String
    public let actorUsername: String?
    public let actorPfpUrl: String?
    public let targetHash: String?
    public let preview: String?
    public let createdAt: Date

    /// Hub returns no stable ID for these aggregated rows. We synthesize
    /// a key from the tuple so SwiftUI's List/ForEach can identify them.
    public var id: String {
        "\(type.rawValue)|\(actorTid)|\(targetHash ?? "")|\(createdAt.timeIntervalSince1970)"
    }

    enum CodingKeys: String, CodingKey {
        case type, preview
        case actorTid = "actor_tid"
        case actorUsername = "actor_username"
        case actorPfpUrl = "actor_pfp_url"
        case targetHash = "target_hash"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(NotificationType.self, forKey: .type)
        self.actorTid = try HubDecode.bigInt(c, forKey: .actorTid)
        self.actorUsername = try c.decodeIfPresent(String.self, forKey: .actorUsername)
        self.actorPfpUrl = try c.decodeIfPresent(String.self, forKey: .actorPfpUrl)
        self.targetHash = try c.decodeIfPresent(String.self, forKey: .targetHash)
        self.preview = try c.decodeIfPresent(String.self, forKey: .preview)
        self.createdAt = try HubDecode.date(c, forKey: .createdAt)
    }
}

public struct NotificationListResponse: Decodable {
    public let notifications: [TribeNotification]

    enum CodingKeys: String, CodingKey {
        case notifications
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decode rows through a forgiving wrapper so a single bad
        // entry — a new server-side type the iOS build doesn't know
        // yet, a missing actor_tid, an unexpected date format —
        // doesn't sink the entire list and surface as
        // "Couldn't load notifications". Bad rows are dropped; the
        // rest still render.
        let raw = try c.decodeIfPresent([ForgivingNotification].self, forKey: .notifications) ?? []
        self.notifications = raw.compactMap(\.value)
    }
}

/// Wrapper that swallows decoding failures for a single notification
/// row so the surrounding list decode keeps going.
private struct ForgivingNotification: Decodable {
    let value: TribeNotification?

    init(from decoder: Decoder) throws {
        self.value = try? TribeNotification(from: decoder)
    }
}

public struct NotificationCountResponse: Decodable {
    public let count: Int
}
