import Foundation

/// One row from `/v1/users` or a single fetch via `/v1/user/:tid`.
public struct User: Decodable, Identifiable, Hashable {
    public let tid: String
    public let custodyAddress: String
    public let username: String?
    public let registeredAt: Date?
    public let followingCount: Int
    public let followersCount: Int
    public let profile: UserProfile?

    public var id: String { tid }

    public var displayName: String {
        if let dn = profile?.displayName, !dn.isEmpty { return dn }
        if let u = username { return "\(u).tribe" }
        return "TID #\(tid)"
    }

    public var initial: String {
        if let dn = profile?.displayName, let first = dn.first { return String(first).uppercased() }
        if let u = username, let first = u.first { return String(first).uppercased() }
        return String(tid.prefix(1))
    }

    enum CodingKeys: String, CodingKey {
        case tid, username, profile
        case custodyAddress = "custody_address"
        case registeredAt = "registered_at"
        case followingCount = "following_count"
        case followersCount = "followers_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tid = try HubDecode.bigInt(c, forKey: .tid)
        self.custodyAddress = try c.decode(String.self, forKey: .custodyAddress)
        self.username = try c.decodeIfPresent(String.self, forKey: .username)
        self.registeredAt = try HubDecode.dateIfPresent(c, forKey: .registeredAt)
        self.followingCount = HubDecode.intCount(c, forKey: .followingCount)
        self.followersCount = HubDecode.intCount(c, forKey: .followersCount)
        self.profile = try c.decodeIfPresent(UserProfile.self, forKey: .profile)
    }
}

public struct UserProfile: Decodable, Hashable {
    public let displayName: String?
    public let bio: String?
    public let pfpUrl: String?
    public let location: String?
    public let url: String?
}

public struct UserListResponse: Decodable {
    public let users: [User]
    public let total: Int?
}
