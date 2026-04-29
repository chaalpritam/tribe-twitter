import Foundation

public struct Crowdfund: Decodable, Identifiable, Hashable {
    public let id: String
    public let creatorTid: String
    public let creatorUsername: String?
    public let title: String
    public let description: String?
    public let goalAmount: Decimal
    public let raisedAmount: Decimal
    public let pledgedAmount: Decimal?
    public let pledgerCount: Int?
    public let currency: String
    public let deadlineAt: Date?
    public let imageUrl: String?
    public let channelId: String?
    public let createdAt: Date

    public var progress: Double {
        let goal = NSDecimalNumber(decimal: goalAmount).doubleValue
        let pledged = pledgedAmount ?? raisedAmount
        let raised = NSDecimalNumber(decimal: pledged).doubleValue
        guard goal > 0 else { return 0 }
        return min(1.0, raised / goal)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, currency
        case creatorTid = "creator_tid"
        case creatorUsername = "creator_username"
        case goalAmount = "goal_amount"
        case raisedAmount = "raised_amount"
        case pledgedAmount = "pledged_amount"
        case pledgerCount = "pledger_count"
        case deadlineAt = "deadline_at"
        case imageUrl = "image_url"
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
        self.goalAmount = HubDecode.decimal(c, forKey: .goalAmount)
        self.raisedAmount = HubDecode.decimal(c, forKey: .raisedAmount)
        // Search endpoint returns `pledged_amount` while the list endpoint
        // returns `raised_amount` — accept either.
        self.pledgedAmount = c.contains(.pledgedAmount) ? HubDecode.decimal(c, forKey: .pledgedAmount) : nil
        self.pledgerCount = (try? c.decodeIfPresent(Int.self, forKey: .pledgerCount)) ?? nil
        self.currency = (try? c.decode(String.self, forKey: .currency)) ?? "USD"
        self.deadlineAt = try HubDecode.dateIfPresent(c, forKey: .deadlineAt)
        self.imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        self.channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        self.createdAt = try HubDecode.date(c, forKey: .createdAt)
    }
}

public struct CrowdfundListResponse: Decodable {
    public let crowdfunds: [Crowdfund]
}
