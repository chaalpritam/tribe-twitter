import Foundation

/// Read-only client for the ephemeral-rollup sequencer. Surfaces
/// instant follow-graph state (with on-chain L1 settlement happening
/// behind the scenes every ~10 s) so the iOS UI can render Follow /
/// Following / Pending without waiting for the next L1 confirmation.
///
/// Writes (POST /v1/follow, /v1/unfollow) require a signature from the
/// user's Solana custody key, which the iOS app doesn't hold today —
/// the Follow button surfaces a "use tribe-app" notice rather than
/// pretending to publish.
public final class ERClient {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// `{ exists, status }`. status is "active", "pending_follow",
    /// "pending_unfollow", or "unknown". UI uses this to render the
    /// Follow button as Following / Pending / Follow.
    public func link(
        followerTID: String,
        followingTID: String
    ) async throws -> ERLinkStatus {
        let url = baseURL.appendingPathComponent("v1/link/\(followerTID)/\(followingTID)")
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw HubError.invalidResponse
        }
        if http.statusCode == 404 || !(200..<300).contains(http.statusCode) {
            return ERLinkStatus(exists: false, status: "unknown")
        }
        return (try? JSONDecoder().decode(ERLinkStatus.self, from: data))
            ?? ERLinkStatus(exists: false, status: "unknown")
    }

    public func profile(_ tid: String) async throws -> ERProfile? {
        let url = baseURL.appendingPathComponent("v1/profile/\(tid)")
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(ERProfile.self, from: data)
    }
}

public struct ERLinkStatus: Decodable {
    public let exists: Bool
    public let status: String

    public var isFollowing: Bool { exists && status == "active" }
    public var isPending: Bool { exists && status == "pending_follow" }
}

public struct ERProfile: Decodable {
    public let tid: Int64
    public let followingCount: Int
    public let followersCount: Int
}
