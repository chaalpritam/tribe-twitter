import Foundation
import SwiftUI

/// Per-tweet on-chain tip aggregate cache. Tweet cards call
/// `ensureLoaded(hash:)` from their .task; the cache lazy-fetches via
/// `/v1/tips/onchain/target/:hash`, dedupes parallel requests for the
/// same hash, and re-publishes `stats` so subscribed cards re-render.
///
/// Stats are session-scoped — there's no eviction beyond `clear()` on
/// signOut. A typical scroll loads 20–50 distinct hashes per session,
/// which is fine to hold in memory.
@MainActor
final class OnchainTipStatsCache: ObservableObject {
    @Published private(set) var stats: [String: OnchainTipStats] = [:]

    /// Hashes with a fetch in flight. Acts as the dedup guard so two
    /// cards rendering the same tweet don't both hit the hub.
    private var inFlight: Set<String> = []

    /// Hashes the hub returned 0 tips for, kept distinct from "still
    /// loading" so the view layer can decide not to render anything
    /// without re-firing the fetch on every appearance.
    private var emptyHashes: Set<String> = []

    private weak var app: AppState?

    init() {}

    func attach(to app: AppState) {
        self.app = app
    }

    /// Cached stats for a tweet hash, or nil if we haven't fetched yet.
    /// Empty results return an OnchainTipStats with zero count, so
    /// the view layer can distinguish "no data yet" (nil) from
    /// "fetched and there are no tips" (zero count).
    func stats(for hash: String) -> OnchainTipStats? {
        if let s = stats[hash] { return s }
        if emptyHashes.contains(hash) { return .empty }
        return nil
    }

    func ensureLoaded(hash: String) {
        if stats[hash] != nil { return }
        if emptyHashes.contains(hash) { return }
        if inFlight.contains(hash) { return }
        inFlight.insert(hash)
        Task { [weak self] in
            await self?.fetch(hash: hash)
        }
    }

    private func fetch(hash: String) async {
        defer { inFlight.remove(hash) }
        guard let app else { return }
        do {
            let s = try await app.api.fetchOnchainTipStats(forTarget: hash)
            if s.tipCount == 0 {
                emptyHashes.insert(hash)
            } else {
                stats[hash] = s
            }
        } catch {
            // Best effort — tip rendering is purely informational, so
            // a hub blip shouldn't poison the card. Don't memoize the
            // failure either, so a future card render gets another shot.
        }
    }

    /// Drop everything. Called from AppState.signOut.
    func clear() {
        stats = [:]
        emptyHashes = []
        inFlight = []
    }
}
