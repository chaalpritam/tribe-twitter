import Foundation

/// Tiny URLSession wrapper that points at a tribe-hub instance.
///
/// All hub endpoints used by tribe-twitter-app are mirrored here so the iOS
/// app can stay read-compatible with the existing hub. Write paths
/// (signed envelopes for tweets, tips, RSVPs, etc.) are deliberately
/// not implemented yet — they need ed25519 signing + blake3 hashing
/// of canonical message bytes, which lives in tribe-twitter-app/src/lib/messages.ts
/// and needs a Swift port before iOS can publish anything.
public final class HubClient {
    public let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let d = JSONDecoder()
        // Hub timestamps are ISO8601 with fractional seconds in some rows
        // and bigint epoch seconds in others. Decode each model field
        // explicitly rather than relying on a global strategy.
        self.decoder = d
    }

    public func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw HubError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HubError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HubError.statusCode(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HubError.decoding(error)
        }
    }
}

public enum HubError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case statusCode(Int, body: String)
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid hub URL"
        case .invalidResponse: return "Invalid response from hub"
        case .statusCode(let code, _): return "Hub returned HTTP \(code)"
        case .decoding(let err): return "Could not decode hub response: \(err.localizedDescription)"
        }
    }
}
