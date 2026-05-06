import Foundation

/// One row from `/v1/dm/conversations/:tid`. The hub joins through
/// the `tids` table so each row already carries the peer's username
/// (when set) and last-message timestamp.
public struct DMConversation: Decodable, Identifiable, Hashable {
    public let id: String
    public let peerTid: String
    public let peerUsername: String?
    public let messageCount: Int
    public let unreadCount: Int
    public let lastMessageAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case peerTid = "peer_tid"
        case peerUsername = "peer_username"
        case messageCount = "message_count"
        case unreadCount = "unread_count"
        case lastMessageAt = "last_message_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.peerTid = try HubDecode.bigInt(c, forKey: .peerTid)
        self.peerUsername = try c.decodeIfPresent(String.self, forKey: .peerUsername)
        self.messageCount = HubDecode.intCount(c, forKey: .messageCount)
        self.unreadCount = HubDecode.intCount(c, forKey: .unreadCount)
        self.lastMessageAt = try HubDecode.dateIfPresent(c, forKey: .lastMessageAt)
    }
}

/// One row from `/v1/dm/messages/:id`. Ciphertext + nonce decrypt
/// client-side using nacl.box.open with our DM private key and the
/// sender's pubkey.
public struct DMMessage: Decodable, Identifiable, Hashable {
    public let hash: String
    public let senderTid: String
    public let ciphertext: String
    public let nonce: String
    public let senderX25519: String?
    public let timestamp: Date

    public var id: String { hash }

    enum CodingKeys: String, CodingKey {
        case hash, ciphertext, nonce, timestamp
        case senderTid = "sender_tid"
        case senderX25519 = "sender_x25519"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hash = try c.decode(String.self, forKey: .hash)
        self.senderTid = try HubDecode.bigInt(c, forKey: .senderTid)
        self.ciphertext = try c.decode(String.self, forKey: .ciphertext)
        self.nonce = try c.decode(String.self, forKey: .nonce)
        self.senderX25519 = try c.decodeIfPresent(String.self, forKey: .senderX25519)
        self.timestamp = try HubDecode.date(c, forKey: .timestamp)
    }
}

/// What a thread view is pointed at. 1:1 conversations and groups
/// share the same UI shell (scrolling list of decrypted bubbles,
/// optional composer); the differences live in fetch/decrypt/send,
/// which the view branches on this enum.
public enum DMTarget: Hashable {
    case oneOnOne(DMConversation)
    case group(DMGroup)

    public var id: String {
        switch self {
        case .oneOnOne(let c): return c.id
        case .group(let g): return g.id
        }
    }

    public var displayTitle: String {
        switch self {
        case .oneOnOne(let c):
            if let u = c.peerUsername, !u.isEmpty { return "\(u).tribe" }
            return "TID #\(c.peerTid)"
        case .group(let g): return g.name
        }
    }
}

/// One row from `/v1/dm/groups/member/:tid`. Groups have a stable
/// human-readable id (matches /^[a-z0-9-]{1,64}$/) plus a name and a
/// member count joined in by the hub.
public struct DMGroup: Decodable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let creatorTid: String
    public let memberCount: Int
    public let createdAt: Date
    public let lastMessageAt: Date?
    public let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case creatorTid = "creator_tid"
        case memberCount = "member_count"
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.creatorTid = try HubDecode.bigInt(c, forKey: .creatorTid)
        self.memberCount = HubDecode.intCount(c, forKey: .memberCount)
        self.createdAt = try HubDecode.date(c, forKey: .createdAt)
        self.lastMessageAt = try HubDecode.dateIfPresent(c, forKey: .lastMessageAt)
        self.unreadCount = HubDecode.intCount(c, forKey: .unreadCount)
    }
}

public struct DMGroupMember: Decodable, Identifiable, Hashable {
    public let tid: String
    public let joinedAt: Date

    public var id: String { tid }

    enum CodingKeys: String, CodingKey {
        case tid
        case joinedAt = "joined_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tid = try HubDecode.bigInt(c, forKey: .tid)
        self.joinedAt = try HubDecode.date(c, forKey: .joinedAt)
    }
}

/// Reply from `/v1/dm/groups/:groupId` — group metadata plus the
/// full member list. Used by the composer to look up each member's
/// x25519 pubkey before per-recipient encryption.
public struct DMGroupDetails: Decodable, Hashable {
    public let id: String
    public let name: String
    public let creatorTid: String
    public let createdAt: Date
    public let members: [DMGroupMember]

    enum CodingKeys: String, CodingKey {
        case id, name, members
        case creatorTid = "creator_tid"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.creatorTid = try HubDecode.bigInt(c, forKey: .creatorTid)
        self.createdAt = try HubDecode.date(c, forKey: .createdAt)
        self.members = try c.decode([DMGroupMember].self, forKey: .members)
    }
}
