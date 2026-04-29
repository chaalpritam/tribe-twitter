import Foundation

public struct Poll: Decodable, Identifiable, Hashable {
    public let id: String
    public let creatorTid: String
    public let question: String
    public let options: [String]
    public let expiresAt: Date?
    public let channelId: String?
    public let createdAt: Date
    public let totalVotes: Int?

    enum CodingKeys: String, CodingKey {
        case id, question, options
        case creatorTid = "creator_tid"
        case expiresAt = "expires_at"
        case channelId = "channel_id"
        case createdAt = "created_at"
        case totalVotes = "total_votes"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.creatorTid = try HubDecode.bigInt(c, forKey: .creatorTid)
        self.question = try c.decode(String.self, forKey: .question)
        self.options = try c.decode([String].self, forKey: .options)
        self.expiresAt = try HubDecode.dateIfPresent(c, forKey: .expiresAt)
        self.channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        self.createdAt = try HubDecode.date(c, forKey: .createdAt)
        self.totalVotes = HubDecode.intCount(c, forKey: .totalVotes)
    }
}

public struct PollListResponse: Decodable {
    public let polls: [Poll]
}

public struct PollDetailResponse: Decodable {
    public let poll: Poll?
    public let tally: [String: Int]?
}
