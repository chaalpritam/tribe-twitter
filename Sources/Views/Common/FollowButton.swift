import SwiftUI

/// Read-only follow indicator. Shows the live follow status pulled
/// from the ER server and, on tap, opens an explanation sheet that
/// directs the user to follow / unfollow from tribe-twitter-app — the iOS app
/// can't sign with the Solana custody key required by the ER follow
/// endpoint.
///
/// Hides itself entirely when targetTID == myTID so a user never sees
/// "follow yourself".
struct FollowButton: View {
    @EnvironmentObject private var app: AppState
    let targetTID: String

    @State private var status: ERLinkStatus?
    @State private var loading = false
    @State private var explaining = false

    private var isMe: Bool { targetTID == app.myTID }
    private var following: Bool { status?.isFollowing == true }
    private var pending: Bool { status?.isPending == true }

    var body: some View {
        if isMe {
            EmptyView()
        } else {
            Button {
                explaining = true
            } label: {
                HStack(spacing: 6) {
                    if loading {
                        ProgressView().controlSize(.mini)
                    } else if pending {
                        Image(systemName: "clock")
                    } else if following {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "plus")
                    }
                    Text(label)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(following ? TribeColor.brand : Color.white)
                .background(
                    Capsule().fill(following ? TribeColor.brand.opacity(0.12) : Color.clear)
                )
                .background(
                    following ? nil : Capsule().fill(TribeColor.brandGradient)
                )
                .overlay(
                    Capsule().stroke(following ? TribeColor.brand.opacity(0.25) : Color.clear, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .task(id: targetTID) { await refresh() }
            .sheet(isPresented: $explaining) {
                FollowExplainerSheet(following: following)
                    .presentationDetents([.medium])
            }
        }
    }

    private var label: String {
        if pending { return "Pending" }
        if following { return "Following" }
        return "Follow"
    }

    @MainActor
    private func refresh() async {
        guard let me = app.myTID, !isMe else { return }
        loading = status == nil
        defer { loading = false }
        status = (try? await app.er.link(followerTID: me, followingTID: targetTID))
    }
}

private struct FollowExplainerSheet: View {
    let following: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)

                Text(following ? "Unfollow on tribe-twitter-app" : "Follow on tribe-twitter-app")
                    .font(.title3.bold())

                Text(following
                     ? "Unfollows must be signed by your Solana custody key. Open tribe-twitter-app on web, find this profile, and tap Unfollow there. The change shows up here as soon as the ER sequencer confirms."
                     : "Follows are written to the ER sequencer with a signature from your Solana custody key. The iOS app doesn't hold that key today, so open tribe-twitter-app on web to follow. The change shows up here in ~50 ms once submitted."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Got it").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}
