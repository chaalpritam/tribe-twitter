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

/// One row from `/v1/tips/onchain/{sent,received}/:tid`. Mirrors a
/// TipRecord PDA from the tip-registry Anchor program — `pda` is the
/// canonical id (one row per on-chain tip), `tx_signature` deep-links
/// to the Solana explorer, and the hub joins `tids.username` of the
/// counterparty so the row can render @name.tribe without an extra
/// lookup.
public struct OnchainTip: Decodable, Identifiable, Hashable {
    public let pda: String
    public let sender: String
    public let recipient: String
    public let senderTid: String
    public let recipientTid: String
    /// Sender's username on a "received" row, recipient's on a "sent"
    /// row. Nil if the counterparty hasn't claimed a username.
    public let counterpartyUsername: String?
    /// Lamports. SOL = lamports / 1_000_000_000.
    public let amount: Int64
    public let tipId: String
    public let targetHash: String?
    public let hasTarget: Bool
    public let txSignature: String
    public let createdAt: Date

    public var id: String { pda }

    enum CodingKeys: String, CodingKey {
        case pda, sender, recipient, amount
        case senderTid = "sender_tid"
        case recipientTid = "recipient_tid"
        case counterpartyUsername = "counterparty_username"
        case tipId = "tip_id"
        case targetHash = "target_hash"
        case hasTarget = "has_target"
        case txSignature = "tx_signature"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.pda = try c.decode(String.self, forKey: .pda)
        self.sender = try c.decode(String.self, forKey: .sender)
        self.recipient = try c.decode(String.self, forKey: .recipient)
        self.senderTid = try HubDecode.bigInt(c, forKey: .senderTid)
        self.recipientTid = try HubDecode.bigInt(c, forKey: .recipientTid)
        self.counterpartyUsername = try c.decodeIfPresent(String.self, forKey: .counterpartyUsername)
        // Amount is BIGINT lamports — same dual-encoding dance as TIDs.
        if let n = try? c.decode(Int64.self, forKey: .amount) {
            self.amount = n
        } else if let s = try? c.decode(String.self, forKey: .amount), let n = Int64(s) {
            self.amount = n
        } else {
            self.amount = 0
        }
        self.tipId = try HubDecode.bigInt(c, forKey: .tipId)
        self.targetHash = try c.decodeIfPresent(String.self, forKey: .targetHash)
        self.hasTarget = (try? c.decode(Bool.self, forKey: .hasTarget)) ?? false
        self.txSignature = try c.decode(String.self, forKey: .txSignature)
        self.createdAt = try HubDecode.date(c, forKey: .createdAt)
    }

    /// Lamports → SOL string with up to 9 fractional digits trimmed.
    public var formattedSol: String {
        let sol = Double(amount) / 1_000_000_000.0
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 9
        return formatter.string(from: NSNumber(value: sol)) ?? "\(sol)"
    }
}

public struct OnchainTipListResponse: Decodable {
    public let tips: [OnchainTip]
}

/// Aggregate tip stats for a single tweet target hash. Decoded from
/// `/v1/tips/onchain/target/:hash` — we ignore the per-tip rows here
/// and only keep the count + total so a card can render a compact
/// "X · 0.05 SOL" alongside the tip button.
public struct OnchainTipStats: Decodable, Hashable {
    public let tipCount: Int
    public let totalLamports: Int64

    enum CodingKeys: String, CodingKey {
        case tipCount = "tip_count"
        case totalLamports = "total_lamports"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tipCount = HubDecode.intCount(c, forKey: .tipCount)
        if let n = try? c.decode(Int64.self, forKey: .totalLamports) {
            self.totalLamports = n
        } else if let s = try? c.decode(String.self, forKey: .totalLamports), let n = Int64(s) {
            self.totalLamports = n
        } else {
            self.totalLamports = 0
        }
    }

    public init(tipCount: Int, totalLamports: Int64) {
        self.tipCount = tipCount
        self.totalLamports = totalLamports
    }

    public static let empty = OnchainTipStats(tipCount: 0, totalLamports: 0)

    public var formattedSol: String {
        let sol = Double(totalLamports) / 1_000_000_000.0
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: sol)) ?? "\(sol)"
    }
}
