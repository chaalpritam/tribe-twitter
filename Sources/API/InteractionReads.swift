import Foundation

/// Per-user state read-backs: have I reacted / bookmarked / voted /
/// RSVPed. Each helper returns nil instead of throwing on 404 so the
/// caller can default to 'unset' without juggling errors.
public extension HubClient {
    // MARK: - Reactions

    public struct ReactionRow: Decodable {
        public let targetHash: String
        public let reactionType: String?
        public let reactedAt: Date?

        enum CodingKeys: String, CodingKey {
            case targetHash = "target_hash"
            case reactionType = "reaction_type"
            case reactedAt = "reacted_at"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.targetHash = try c.decode(String.self, forKey: .targetHash)
            self.reactionType = try c.decodeIfPresent(String.self, forKey: .reactionType)
            self.reactedAt = try HubDecode.dateIfPresent(c, forKey: .reactedAt)
        }
    }

    /// Bulk read of a TID's currently-active reactions. Filtered to a
    /// specific reaction subtype when `type` is non-nil — e.g. `"1"` for
    /// likes. Used at home-feed mount time to populate the heart icon
    /// on every visible tweet without hitting the hub once per card.
    func fetchMyReactions(tid: String, type: String? = nil) async throws -> [ReactionRow] {
        struct R: Decodable { let reactions: [ReactionRow] }
        var query: [String: String] = [:]
        if let type { query["type"] = type }
        let r: R = try await get("v1/users/\(tid)/reactions", query: query)
        return r.reactions
    }

    // MARK: - Bookmarks

    public struct BookmarkRow: Decodable {
        public let targetHash: String

        enum CodingKeys: String, CodingKey {
            case targetHash = "target_hash"
        }
    }

    func fetchMyBookmarks(tid: String) async throws -> [BookmarkRow] {
        struct R: Decodable { let bookmarks: [BookmarkRow] }
        let r: R = try await get("v1/bookmarks/\(tid)")
        return r.bookmarks
    }

    // MARK: - Per-poll vote

    public struct PollVote: Decodable {
        public let optionIndex: Int
        public let votedAt: Date?

        enum CodingKeys: String, CodingKey {
            case optionIndex = "option_index"
            case votedAt = "voted_at"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.optionIndex = try c.decode(Int.self, forKey: .optionIndex)
            self.votedAt = try HubDecode.dateIfPresent(c, forKey: .votedAt)
        }
    }

    /// Returns the TID's vote on a specific poll, or nil if they
    /// haven't voted (hub returns 404).
    func fetchMyPollVote(pollId: String, tid: String) async -> PollVote? {
        try? await get("v1/polls/\(pollId)/vote/\(tid)")
    }

    // MARK: - Per-event RSVP

    public struct EventRSVP: Decodable {
        public let status: String
        public let rsvpedAt: Date?

        enum CodingKeys: String, CodingKey {
            case status
            case rsvpedAt = "rsvped_at"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.status = try c.decode(String.self, forKey: .status)
            self.rsvpedAt = try HubDecode.dateIfPresent(c, forKey: .rsvpedAt)
        }
    }

    /// Returns the TID's RSVP on a specific event, or nil if they
    /// haven't RSVPed.
    func fetchMyEventRSVP(eventId: String, tid: String) async -> EventRSVP? {
        try? await get("v1/events/\(eventId)/rsvp/\(tid)")
    }
}
