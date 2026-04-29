import Foundation

/// Hub write paths. Every protocol-state-changing action on the
/// network goes through `POST /v1/submit` carrying a signed envelope.
/// Wallet-style on-chain transactions (Solana TID register, on-chain
/// tip) need a separate Solana wallet flow that isn't wired up yet.
extension HubClient {
    /// POST a signed envelope to /v1/submit. Returns the new content
    /// hash the hub assigned (base64). Throws `HubError.statusCode`
    /// with the hub's error body on rejection.
    @discardableResult
    func submit(envelope: Data) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/submit"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = envelope

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HubError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HubError.statusCode(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        struct Reply: Decodable { let hash: String? }
        if let reply = try? JSONDecoder().decode(Reply.self, from: data), let h = reply.hash {
            return h
        }
        return ""
    }

    // MARK: - Convenience builders

    /// Publish a tweet. Optional reply parent hash and channel id
    /// match what the existing tribe-app composer sends. The hub
    /// requires every TWEET_ADD to carry a channel_id; when the
    /// caller doesn't have one, fall back to the reserved "general"
    /// channel, which is what tribe-app's composer does.
    @discardableResult
    func publishTweet(
        text: String,
        as appKey: AppKey,
        tid: String,
        parentHash: String? = nil,
        channelId: String? = nil,
        embeds: [String]? = nil
    ) async throws -> String {
        var body: [String: Any] = [
            "text": text,
            "channel_id": channelId ?? "general",
        ]
        if let parentHash { body["parent_hash"] = parentHash }
        if let embeds, !embeds.isEmpty { body["embeds"] = embeds }
        let envelope = try MessageSigner.sign(
            type: MessageType.tweetAdd.rawValue,
            tid: tid,
            body: body,
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func deleteTweet(
        hash: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.tweetRemove.rawValue,
            tid: tid,
            body: ["target_hash": hash],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    /// Like a tweet (REACTION_ADD with reaction.type = 1).
    @discardableResult
    func likeTweet(
        hash: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.reactionAdd.rawValue,
            tid: tid,
            body: ["parent_hash": hash, "reaction": ["type": 1]],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func unlikeTweet(
        hash: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.reactionRemove.rawValue,
            tid: tid,
            body: ["parent_hash": hash, "reaction": ["type": 1]],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func bookmark(
        hash: String,
        as appKey: AppKey,
        tid: String,
        add: Bool
    ) async throws -> String {
        let type = add ? MessageType.bookmarkAdd : MessageType.bookmarkRemove
        let envelope = try MessageSigner.sign(
            type: type.rawValue,
            tid: tid,
            body: ["target_hash": hash],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func voteOnPoll(
        pollId: String,
        optionIndex: Int,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.pollVote.rawValue,
            tid: tid,
            body: ["poll_id": pollId, "option_index": optionIndex],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func rsvp(
        eventId: String,
        status: String, // "yes" | "no" | "maybe"
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.eventRSVP.rawValue,
            tid: tid,
            body: ["event_id": eventId, "status": status],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func claimTask(
        taskId: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.taskClaim.rawValue,
            tid: tid,
            body: ["task_id": taskId],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func completeTask(
        taskId: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.taskComplete.rawValue,
            tid: tid,
            body: ["task_id": taskId],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func pledgeCrowdfund(
        crowdfundId: String,
        amount: Decimal,
        currency: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.crowdfundPledge.rawValue,
            tid: tid,
            body: [
                "crowdfund_id": crowdfundId,
                "amount": NSDecimalNumber(decimal: amount).doubleValue,
                "currency": currency,
            ],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    /// Publish a TIP_ADD envelope (off-chain receipt). The on-chain
    /// SOL transfer through tip-registry isn't wired up here yet —
    /// hubs accept envelopes without a tx_signature.
    @discardableResult
    func publishTip(
        recipientTid: String,
        amount: Decimal,
        currency: String,
        targetHash: String? = nil,
        txSignature: String? = nil,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        var body: [String: Any] = [
            "recipient_tid": recipientTid.numericIfFits(),
            "amount": NSDecimalNumber(decimal: amount).doubleValue,
            "currency": currency,
        ]
        if let targetHash { body["target_hash"] = targetHash }
        if let txSignature { body["tx_signature"] = txSignature }
        let envelope = try MessageSigner.sign(
            type: MessageType.tipAdd.rawValue,
            tid: tid,
            body: body,
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    /// Push a single profile field (USER_DATA_ADD type 7). Used by
    /// the Settings screen to update displayName / bio / pfpUrl.
    @discardableResult
    func updateProfile(
        field: String,
        value: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.userDataAdd.rawValue,
            tid: tid,
            body: ["field": field, "value": value],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }
}

private extension String {
    func numericIfFits() -> Any {
        if let n = Int64(self), abs(n) < 9_007_199_254_740_992 {
            return n
        }
        return self
    }
}
