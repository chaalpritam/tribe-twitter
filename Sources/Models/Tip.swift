import Foundation

public struct Tip: Decodable, Identifiable, Hashable {
    public let hash: String
    public let senderTid: String
    public let recipientTid: String
    public let targetHash: String?
    public let amount: Decimal
    public let currency: String
    public let txSignature: String?
    public let sentAt: Date

    public var id: String { hash }

    enum CodingKeys: String, CodingKey {
        case hash, amount, currency
        case senderTid = "sender_tid"
        case recipientTid = "recipient_tid"
        case targetHash = "target_hash"
        case txSignature = "tx_signature"
        case sentAt = "sent_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hash = try c.decode(String.self, forKey: .hash)
        self.senderTid = try HubDecode.bigInt(c, forKey: .senderTid)
        self.recipientTid = try HubDecode.bigInt(c, forKey: .recipientTid)
        self.targetHash = try c.decodeIfPresent(String.self, forKey: .targetHash)
        self.amount = HubDecode.decimal(c, forKey: .amount)
        self.currency = (try? c.decode(String.self, forKey: .currency)) ?? "SOL"
        self.txSignature = try c.decodeIfPresent(String.self, forKey: .txSignature)
        self.sentAt = try HubDecode.date(c, forKey: .sentAt)
    }
}

public struct TipListResponse: Decodable {
    public let tips: [Tip]
}
