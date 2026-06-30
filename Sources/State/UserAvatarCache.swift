import Foundation
import TribeCore
import SwiftUI

/// Per-TID profile-picture URL cache. Tweet, DM, and tip rows only
/// know a counterparty TID — they don't carry the full User payload
/// — so we lazy-fetch `/v1/user/:tid` on first sight and republish
/// the resolved pfp URL so subscribed avatars swap in the image as
/// soon as it lands.
///
/// Misses (no profile, no pfpUrl, fetch failure) are memoized in a
/// separate set so we don't keep retrying for a user who simply
/// hasn't uploaded an avatar.
@MainActor
final class UserAvatarCache: ObservableObject {
    @Published private(set) var pfpUrls: [String: URL] = [:]

    private var inFlight: Set<String> = []
    private var missing: Set<String> = []

    private weak var app: AppState?

    init() {}

    func attach(to app: AppState) {
        self.app = app
    }

    /// Resolved pfp URL for a TID, or nil if we haven't fetched yet,
    /// the user has no pfp set, or the fetch failed.
    func pfpUrl(for tid: String) -> URL? {
        pfpUrls[tid]
    }

    /// Fire-and-forget warm-up. Idempotent — second and later calls
    /// for the same TID are no-ops while the first fetch is in
    /// flight or after we've recorded a hit / miss.
    func ensureLoaded(tid: String) {
        if pfpUrls[tid] != nil { return }
        if missing.contains(tid) { return }
        if inFlight.contains(tid) { return }
        inFlight.insert(tid)
        Task { [weak self] in
            await self?.fetch(tid: tid)
        }
    }

    /// Pre-populate the cache when a caller already has the User
    /// object (ProfileView, Search, Explore) so the cache benefits
    /// from work the screen already did and we skip the round trip.
    func record(tid: String, pfpUrl: URL?) {
        inFlight.remove(tid)
        if let pfpUrl {
            pfpUrls[tid] = pfpUrl
            missing.remove(tid)
        } else {
            missing.insert(tid)
        }
    }

    private func fetch(tid: String) async {
        defer { inFlight.remove(tid) }
        guard let app else { return }
        do {
            let user = try await app.api.fetchUser(tid)
            if let raw = user.profile?.pfpUrl,
               let url = app.api.resolveMediaURL(raw) {
                pfpUrls[tid] = url
            } else {
                missing.insert(tid)
            }
        } catch {
            // Best effort — the gradient fallback is fine while the
            // hub is unreachable. Don't memoize the failure so the
            // next render gets another shot.
        }
    }

    /// Drop everything. Called from AppState.signOut.
    func clear() {
        pfpUrls = [:]
        missing = []
        inFlight = []
    }
}
