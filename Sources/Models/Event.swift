import Foundation

public struct Event: Decodable, Identifiable, Hashable {
    public let id: String
    public let creatorTid: String
    public let creatorUsername: String?
    public let title: String
    public let description: String?
    public let startsAt: Date
    public let endsAt: Date?
    public let locationText: String?
    public let latitude: Double?
    public let longitude: Double?
    public let imageUrl: String?
    public let channelId: String?
    public let createdAt: Date
    public let yesCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description, latitude, longitude
        case creatorTid = "creator_tid"
        case creatorUsername = "creator_username"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case locationText = "location_text"
        case imageUrl = "image_url"
        case channelId = "channel_id"
        case createdAt = "created_at"
        case yesCount = "yes_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.creatorTid = try HubDecode.bigInt(c, forKey: .creatorTid)
        self.creatorUsername = try c.decodeIfPresent(String.self, forKey: .creatorUsername)
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.startsAt = try HubDecode.date(c, forKey: .startsAt)
        self.endsAt = try HubDecode.dateIfPresent(c, forKey: .endsAt)
        self.locationText = try c.decodeIfPresent(String.self, forKey: .locationText)
        self.latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        self.imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        self.channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        self.createdAt = try HubDecode.date(c, forKey: .createdAt)
        self.yesCount = HubDecode.intCount(c, forKey: .yesCount)
    }
}

public struct EventListResponse: Decodable {
    public let events: [Event]
}
