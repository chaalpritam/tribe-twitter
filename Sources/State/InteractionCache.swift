import Foundation
import SwiftUI

/// Session-scoped cache of "have I liked / bookmarked this tweet"
/// state. Hangs off AppState so every TweetCardView can ask without
/// refetching, and so write paths (like, unlike, bookmark, unbookmark)
/// can keep the cache consistent without round-tripping the hub for
/// the answer they just produced.
///
/// Loaded lazily the first time a tweet card tries to render with
/// the user's TID known. Re-loadable via `refresh()` after
/// background → foreground transitions or explicit pull-to-refresh.
@MainActor
final class InteractionCache: ObservableObject {
    @Published private(set) var likedHashes: Set<String> = []
    @Published private(set) var bookmarkedHashes: Set<String> = []
    @Published private(set) var loaded = false

    /// Set by AppState immediately after init. Weak so the cache
    /// doesn't outlive the app state in tests.
    private weak var app: AppState?

    init() {}

    func attach(to app: AppState) {
        self.app = app
    }

    func contains(liked hash: String) -> Bool { likedHashes.contains(hash) }
    func contains(bookmarked hash: String) -> Bool { bookmarkedHashes.contains(hash) }

    func setLiked(_ liked: Bool, hash: String) {
        if liked { likedHashes.insert(hash) } else { likedHashes.remove(hash) }
    }

    func setBookmarked(_ bookmarked: Bool, hash: String) {
        if bookmarked { bookmarkedHashes.insert(hash) } else { bookmarkedHashes.remove(hash) }
    }

    /// Pulls the user's like + bookmark sets from the hub. Idempotent
    /// — safe to call repeatedly on view appear; bails fast when the
    /// user has no TID and replaces the in-memory sets atomically on
    /// success.
    func ensureLoaded() async {
        guard !loaded else { return }
        await refresh()
    }

    func refresh() async {
        guard let app, let tid = app.myTID else {
            likedHashes = []
            bookmarkedHashes = []
            loaded = false
            return
        }
        async let reactionsTask = (try? await app.api.fetchMyReactions(tid: tid, type: "1")) ?? []
        async let bookmarksTask = (try? await app.api.fetchMyBookmarks(tid: tid)) ?? []
        let (reactions, bookmarks) = await (reactionsTask, bookmarksTask)
        self.likedHashes = Set(reactions.map(\.targetHash))
        self.bookmarkedHashes = Set(bookmarks.map(\.targetHash))
        self.loaded = true
    }

    /// Drop everything. Called from AppState.signOut.
    func clear() {
        likedHashes = []
        bookmarkedHashes = []
        loaded = false
    }
}
