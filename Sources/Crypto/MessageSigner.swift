import Foundation

/// Builds a signed protocol envelope identical in shape to what
/// `tribe-app/src/lib/messages.ts:submitTypedEnvelope` produces.
///
/// Wire format the hub validates against:
///
/// ```
/// {
///   protocolVersion: 1,
///   data: { type, tid, timestamp, network, body },
///   dataB64:   base64( UTF-8 JSON of `data` ),
///   hash:      base64( blake3(dataB64-decoded bytes) ),
///   signature: base64( ed25519_sign(hash, signingSeed) ),
///   signer:    base64( ed25519_public_key )
/// }
/// ```
///
/// The hub recomputes the hash from `dataB64` and verifies the
/// signature, so as long as the bytes inside `dataB64` are exactly
/// what we hashed, key ordering / whitespace in the outer wrapper
/// don't matter.
enum MessageSigner {
    /// Network int matching DEVNET in the protocol enum.
    static let network: Int = 2

    /// Build + sign an envelope. `body` is a JSON-shaped dictionary
    /// of raw values (String / Int / Double / [Any] / [String: Any]
    /// / NSNumber). The resulting Data is a JSON object ready to
    /// POST to /v1/submit.
    static func sign(
        type: Int,
        tid: String,
        body: [String: Any],
        appKey: AppKey,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) throws -> Data {
        // Build the inner `data` object. We serialize it with
        // .sortedKeys + .withoutEscapingSlashes so the bytes inside
        // `dataB64` are canonical regardless of how the body keys
        // were inserted. This is what gets hashed and signed.
        let tidValue: Any = tid.numericIfFits()
        let dataObject: [String: Any] = [
            "type": type,
            "tid": tidValue,
            "timestamp": timestamp,
            "network": network,
            "body": body,
        ]

        let dataBytes = try JSONSerialization.data(
            withJSONObject: dataObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )

        let hashBytes = Blake3.hash(dataBytes)
        let signature = try appKey.sign(hashBytes)

        let envelope: [String: Any] = [
            "protocolVersion": 1,
            "data": dataObject,
            "dataB64": dataBytes.base64EncodedString(),
            "hash": hashBytes.base64EncodedString(),
            "signature": signature.base64EncodedString(),
            "signer": appKey.publicKey.rawRepresentation.base64EncodedString(),
        ]

        return try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }
}

private extension String {
    /// Hub serializes BIGINT TIDs as either numbers or strings. JS's
    /// JSON.stringify of `data.tid = 12345` produces `"tid":12345`
    /// (number). To keep our hashed bytes equivalent we emit a number
    /// when the string fits in an Int64 (safe range is ±2^53 in JS,
    /// but every TID we'll see in practice is well under that), and
    /// fall back to a string for anything bigger.
    func numericIfFits() -> Any {
        if let n = Int64(self), abs(n) < 9_007_199_254_740_992 {
            return n
        }
        return self
    }
}

// MARK: - Strongly typed envelope kinds

/// Integer message types the hub recognizes. Matches the `MessageType`
/// enum in tribe-protocol; we only enumerate the ones the iOS app
/// actually publishes.
enum MessageType: Int {
    case tweetAdd = 1
    case tweetRemove = 2
    case reactionAdd = 3
    case reactionRemove = 4
    case userDataAdd = 7
    case channelAdd = 9
    case channelJoin = 10
    case channelLeave = 11
    case dmKeyRegister = 12
    case dmSend = 13
    case bookmarkAdd = 14
    case bookmarkRemove = 15
    case pollAdd = 16
    case pollVote = 17
    case eventAdd = 18
    case eventRSVP = 19
    case taskAdd = 20
    case taskClaim = 21
    case taskComplete = 22
    case crowdfundAdd = 23
    case crowdfundPledge = 24
    case tipAdd = 25
    case dmGroupCreate = 26
    case dmGroupSend = 27
    case dmRead = 28
}
