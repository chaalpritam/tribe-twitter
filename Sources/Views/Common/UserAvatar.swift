import SwiftUI
import TribeCore

/// AvatarView for cases where the caller knows a TID but not the
/// pfp URL up front (feed rows, DM list, tip rows). Pulls the
/// resolved pfp URL out of the shared `UserAvatarCache`, falls back
/// to the gradient + initial when the cache hasn't seen this TID
/// yet, and triggers a lazy fetch on first appearance so the photo
/// swaps in once it lands.
///
/// Callers that already hold the User payload (ProfileView, search,
/// explore) should keep using `AvatarView` directly with `pfpURL:`
/// to avoid a redundant round trip.
struct UserAvatar: View {
    let tid: String
    let initial: String
    var size: CGFloat = 40
    var seed: String? = nil

    @EnvironmentObject private var userAvatars: UserAvatarCache

    var body: some View {
        AvatarView(
            initial: initial,
            size: size,
            pfpURL: userAvatars.pfpUrl(for: tid),
            seed: seed
        )
        .task(id: tid) { userAvatars.ensureLoaded(tid: tid) }
    }
}
