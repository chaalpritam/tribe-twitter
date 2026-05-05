import Foundation

/// Hub write paths. Every protocol-state-changing action on the
/// network goes through `POST /v1/submit` carrying a signed envelope.
/// Wallet-style on-chain transactions (Solana TID register, on-chain
/// tip) need a separate Solana wallet flow that isn't wired up yet.
extension HubClient {
    /// POST a binary blob to /v1/upload. Returns the SHA-256 hex hash
    /// the hub assigned, which callers stitch into a tweet's `embeds`
    /// array as `"media:<hash>"`. Hub enforces ≤5 MB and only accepts
    /// the four common image MIME types — caller is responsible for
    /// downscaling / re-encoding before calling. Constructs a minimal
    /// multipart/form-data body by hand to avoid pulling in a
    /// dependency just for one call.
    func uploadMedia(data: Data, contentType: String, filename: String = "upload") async throws -> String {
        let boundary = "----TribeIOSBoundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60
        request.httpBody = body

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HubError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw HubError.statusCode(http.statusCode, body: String(data: respData, encoding: .utf8) ?? "")
        }
        struct Reply: Decodable { let hash: String }
        let reply = try JSONDecoder().decode(Reply.self, from: respData)
        return reply.hash
    }

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

    /// Subtypes of a REACTION envelope. Matches the web client's
    /// `ReactionSubtype` in tribe-app/src/lib/messages.ts and what the
    /// hub stores in `messages.text` for type=3 / type=4 rows.
    ///
    /// Note: REACTION_REMOVE on the hub clears EVERY reaction the user
    /// has on a target regardless of subtype, so toggling off a retweet
    /// also clears a like on the same tweet. Acceptable for v1 — matches
    /// the web behavior.
    enum ReactionSubtype: Int {
        case like = 1
        case retweet = 2
    }

    /// Like a tweet (REACTION_ADD with body.type = 1).
    @discardableResult
    func likeTweet(
        hash: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        try await react(targetHash: hash, subtype: .like, add: true, as: appKey, tid: tid)
    }

    @discardableResult
    func unlikeTweet(
        hash: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        try await react(targetHash: hash, subtype: .like, add: false, as: appKey, tid: tid)
    }

    /// Retweet (REACTION_ADD with body.type = 2). Profile feeds project
    /// retweeted tweets under the original's body with retweeted_by_*
    /// metadata so the recipient can render an "X retweeted" header.
    @discardableResult
    func retweet(
        hash: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        try await react(targetHash: hash, subtype: .retweet, add: true, as: appKey, tid: tid)
    }

    @discardableResult
    func unretweet(
        hash: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        try await react(targetHash: hash, subtype: .retweet, add: false, as: appKey, tid: tid)
    }

    /// Internal: build + submit a signed REACTION envelope. Wire body
    /// shape is `{type: <subtype>, target_hash: <hash>}` — flat —
    /// matching what the hub's submit.ts validates against. Subtype is
    /// included on REMOVE too so the wire shape stays consistent even
    /// though the hub ignores it on remove.
    @discardableResult
    private func react(
        targetHash hash: String,
        subtype: ReactionSubtype,
        add: Bool,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: (add ? MessageType.reactionAdd : MessageType.reactionRemove).rawValue,
            tid: tid,
            body: ["type": subtype.rawValue, "target_hash": hash],
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

    // MARK: - Direct messages

    /// Register the user's x25519 public key with the hub so other
    /// clients can encrypt DMs to this TID. Idempotent — overwrites
    /// any previous key for the same TID. Posts to /v1/dm/register-key
    /// rather than /v1/submit (the dedicated route validates the
    /// envelope shape exactly the same way but writes to the
    /// `dm_keys` table directly).
    @discardableResult
    func registerDMKey(
        publicKey x25519Pub: Data,
        as appKey: AppKey,
        tid: String
    ) async throws -> Data {
        let envelope = try MessageSigner.sign(
            type: MessageType.dmKeyRegister.rawValue,
            tid: tid,
            body: ["x25519_pubkey": x25519Pub.base64EncodedString()],
            appKey: appKey
        )
        return try await postRaw(path: "v1/dm/register-key", envelope: envelope)
    }

    /// Send an encrypted DM. Caller is responsible for producing the
    /// ciphertext (`nacl.box(plaintext, nonce, recipientPub, ourPriv)`)
    /// and the matching 24-byte nonce.
    @discardableResult
    func sendDM(
        recipientTID: String,
        ciphertext: Data,
        nonce: Data,
        senderX25519: Data,
        as appKey: AppKey,
        tid: String
    ) async throws -> Data {
        let body: [String: Any] = [
            "recipient_tid": recipientTID.numericIfFitsInt(),
            "ciphertext": ciphertext.base64EncodedString(),
            "nonce": nonce.base64EncodedString(),
            "sender_x25519": senderX25519.base64EncodedString(),
        ]
        let envelope = try MessageSigner.sign(
            type: MessageType.dmSend.rawValue,
            tid: tid,
            body: body,
            appKey: appKey
        )
        return try await postRaw(path: "v1/dm/send", envelope: envelope)
    }

    /// Mark progress through a conversation by recording the most
    /// recent message hash the user has seen. Posts a DM_READ envelope
    /// to /v1/dm/read; the hub upserts a row in `dm_read_receipts`
    /// keyed by (tid, conversation_id).
    @discardableResult
    func markDMRead(
        conversationId: String,
        lastReadHash: String,
        as appKey: AppKey,
        tid: String
    ) async throws -> Data {
        let envelope = try MessageSigner.sign(
            type: MessageType.dmRead.rawValue,
            tid: tid,
            body: [
                "conversation_id": conversationId,
                "last_read_hash": lastReadHash,
            ],
            appKey: appKey
        )
        return try await postRaw(path: "v1/dm/read", envelope: envelope)
    }

    /// Internal — POST a signed envelope to a non-/v1/submit route
    /// and return the raw response body so the caller can parse the
    /// route-specific reply (e.g. the conversation_id for DM_SEND).
    private func postRaw(path: String, envelope: Data) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
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
        return data
    }

    // MARK: - Channel / poll / event / task / crowdfund creation

    /// Create a new channel. Hub validates `channelId` against
    /// `^[a-z0-9-]{1,64}$`, rejects the reserved id "general", and
    /// requires kind to be CITY (2) or INTEREST (3) — GENERAL (1) is
    /// not user-creatable. lat/lng only persist for CITY.
    @discardableResult
    func createChannel(
        channelId: String,
        name: String,
        description: String?,
        kind: Int,
        latitude: Double? = nil,
        longitude: Double? = nil,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        var body: [String: Any] = [
            "channel_id": channelId,
            "name": name,
            "kind": kind,
        ]
        if let description, !description.isEmpty { body["description"] = description }
        if kind == 2 {
            if let latitude { body["latitude"] = latitude }
            if let longitude { body["longitude"] = longitude }
        }
        let envelope = try MessageSigner.sign(
            type: MessageType.channelAdd.rawValue,
            tid: tid,
            body: body,
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func joinChannel(_ channelId: String, as appKey: AppKey, tid: String) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.channelJoin.rawValue,
            tid: tid,
            body: ["channel_id": channelId],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func leaveChannel(_ channelId: String, as appKey: AppKey, tid: String) async throws -> String {
        let envelope = try MessageSigner.sign(
            type: MessageType.channelLeave.rawValue,
            tid: tid,
            body: ["channel_id": channelId],
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func createPoll(
        pollId: String,
        question: String,
        options: [String],
        expiresAt: Date?,
        channelId: String?,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        var body: [String: Any] = [
            "poll_id": pollId,
            "question": question,
            "options": options,
        ]
        if let expiresAt { body["expires_at"] = Int(expiresAt.timeIntervalSince1970) }
        if let channelId, !channelId.isEmpty { body["channel_id"] = channelId }
        let envelope = try MessageSigner.sign(
            type: MessageType.pollAdd.rawValue,
            tid: tid,
            body: body,
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func createEvent(
        eventId: String,
        title: String,
        description: String?,
        startsAt: Date,
        endsAt: Date?,
        locationText: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        channelId: String?,
        imageURL: String?,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        var body: [String: Any] = [
            "event_id": eventId,
            "title": title,
            "starts_at": Int(startsAt.timeIntervalSince1970),
        ]
        if let description, !description.isEmpty { body["description"] = description }
        if let endsAt { body["ends_at"] = Int(endsAt.timeIntervalSince1970) }
        if let locationText, !locationText.isEmpty { body["location_text"] = locationText }
        if let latitude { body["latitude"] = latitude }
        if let longitude { body["longitude"] = longitude }
        if let channelId, !channelId.isEmpty { body["channel_id"] = channelId }
        if let imageURL, !imageURL.isEmpty { body["image_url"] = imageURL }
        let envelope = try MessageSigner.sign(
            type: MessageType.eventAdd.rawValue,
            tid: tid,
            body: body,
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func createTask(
        taskId: String,
        title: String,
        description: String?,
        rewardText: String?,
        channelId: String?,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        var body: [String: Any] = [
            "task_id": taskId,
            "title": title,
        ]
        if let description, !description.isEmpty { body["description"] = description }
        if let rewardText, !rewardText.isEmpty { body["reward_text"] = rewardText }
        if let channelId, !channelId.isEmpty { body["channel_id"] = channelId }
        let envelope = try MessageSigner.sign(
            type: MessageType.taskAdd.rawValue,
            tid: tid,
            body: body,
            appKey: appKey
        )
        return try await submit(envelope: envelope)
    }

    @discardableResult
    func createCrowdfund(
        crowdfundId: String,
        title: String,
        description: String?,
        goalAmount: Double,
        currency: String?,
        deadline: Date?,
        imageURL: String?,
        channelId: String?,
        as appKey: AppKey,
        tid: String
    ) async throws -> String {
        var body: [String: Any] = [
            "crowdfund_id": crowdfundId,
            "title": title,
            "goal_amount": goalAmount,
        ]
        if let description, !description.isEmpty { body["description"] = description }
        if let currency, !currency.isEmpty { body["currency"] = currency }
        if let deadline { body["deadline_at"] = Int(deadline.timeIntervalSince1970) }
        if let imageURL, !imageURL.isEmpty { body["image_url"] = imageURL }
        if let channelId, !channelId.isEmpty { body["channel_id"] = channelId }
        let envelope = try MessageSigner.sign(
            type: MessageType.crowdfundAdd.rawValue,
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

    /// Same as numericIfFits but typed Any so JSONSerialization keeps
    /// emitting a JSON number rather than wrapping in NSNumber.
    func numericIfFitsInt() -> Any { numericIfFits() }
}
