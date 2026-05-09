import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var app: AppState
    @State private var rows: [TribeNotification] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if app.myTID == nil {
                EmptyStateView(
                    symbol: "person.crop.circle.badge.exclamationmark",
                    title: "Sign in required",
                    message: "Set your TID in Settings to see notifications addressed to you."
                )
            } else if loading {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { _ in NotifSkeleton() }
                    }
                    .padding(.vertical, 8)
                }
            } else if let error {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load notifications",
                    message: error,
                    action: ("Retry", load)
                )
            } else if rows.isEmpty {
                EmptyStateView(
                    symbol: "bell",
                    title: "All caught up",
                    message: "Replies, reactions, tips, RSVPs, and other activity will appear here."
                )
            } else {
                List(aggregate(rows)) { agg in
                    NotifRow(agg: agg)
                }
                .listStyle(.plain)
            }
        }
        .background(TribeColor.pageBackground)
        .navigationTitle("Activity")
        .refreshable { await refresh() }
        .task { load() }
    }

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard let tid = app.myTID else { loading = false; return }
        loading = rows.isEmpty
        error = nil
        do {
            rows = try await app.api.fetchNotifications(tid)
            // Stamp the read mark only after a successful fetch so a
            // network error doesn't silently mark everything read.
            app.markNotificationsRead(tid: tid)
        } catch HubError.statusCode(404, _) {
            // Some hubs 404 a TID with no activity. Treat as empty.
            rows = []
            app.markNotificationsRead(tid: tid)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

/// One row in the rendered notifications list. Holds the most recent
/// underlying event as `primary` plus a count of additional actors
/// that were folded in by aggregation. `additionalActorCount` is 0
/// when the row stands alone.
private struct AggregatedNotification: Identifiable {
    let primary: TribeNotification
    let additionalActorCount: Int
    var id: String { "\(primary.id)|+\(additionalActorCount)" }
}

/// Collapse same-kind events on the same target into a single row,
/// e.g. five reactions on one tweet become "@alice and 4 others
/// reacted to your tweet". Replies and mentions stay un-aggregated
/// because each one carries distinct content the user likely wants
/// to see individually. Input must be sorted newest-first.
private func aggregate(_ rows: [TribeNotification]) -> [AggregatedNotification] {
    var result: [AggregatedNotification] = []
    var indexByGroup: [String: Int] = [:]
    for row in rows {
        let groupable: Bool
        switch row.type {
        case .reply, .mention:
            groupable = false
        case .reaction, .tip, .follow, .pollVote,
             .eventRsvp, .taskClaim, .taskComplete, .crowdfundPledge:
            groupable = true
        }
        // Follow has no target_hash so all follows aggregate into one
        // bucket. Other groupable types key on (type, target_hash) so
        // separate tweets / polls / events stay independent.
        let key = groupable
            ? "\(row.type.rawValue)|\(row.targetHash ?? "")"
            : row.id
        if let idx = indexByGroup[key] {
            result[idx] = AggregatedNotification(
                primary: result[idx].primary,
                additionalActorCount: result[idx].additionalActorCount + 1
            )
        } else {
            indexByGroup[key] = result.count
            result.append(AggregatedNotification(primary: row, additionalActorCount: 0))
        }
    }
    return result
}

private struct NotifRow: View {
    let agg: AggregatedNotification
    private var row: TribeNotification { agg.primary }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        initial: avatarInitial,
                        size: 40,
                        pfpURL: row.actorPfpUrl.flatMap(URL.init(string:))
                    )
                    Image(systemName: row.type.symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.accentColor))
                        .overlay(Circle().stroke(TribeColor.pageBackground, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let preview = row.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(RelativeTime.short(row.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actorDisplay: String {
        if let u = row.actorUsername, !u.isEmpty { return "\(u).tribe" }
        return "TID #\(row.actorTid)"
    }

    private var avatarInitial: String {
        if let u = row.actorUsername, let first = u.first { return String(first).uppercased() }
        return String(row.actorTid.prefix(1))
    }

    private var headline: String {
        if agg.additionalActorCount == 0 {
            return "\(actorDisplay) \(row.type.label)"
        }
        let others = agg.additionalActorCount
        return "\(actorDisplay) and \(others) other\(others == 1 ? "" : "s") \(row.type.label)"
    }

    @ViewBuilder
    private var destination: some View {
        // Tweet-related events have a target_hash pointing at the
        // tweet that was reacted to, replied to, mentioned in, or
        // tipped — push the thread view so the user lands on the
        // actual content. Everything else falls back to the actor's
        // profile (poll/event/task/crowdfund detail views don't
        // exist yet).
        switch row.type {
        case .reaction, .reply, .mention, .tip:
            if let hash = row.targetHash, !hash.isEmpty {
                TweetByHashView(hash: hash)
            } else {
                ProfileView(tid: row.actorTid)
            }
        case .follow, .pollVote, .eventRsvp, .taskClaim, .taskComplete, .crowdfundPledge:
            ProfileView(tid: row.actorTid)
        }
    }
}

/// Loader view: fetches a tweet by hash and shows the detail view.
/// Used by notification rows where we only carry the target_hash and
/// don't want to pre-fetch every tweet at list-load time.
private struct TweetByHashView: View {
    @EnvironmentObject private var app: AppState
    let hash: String

    @State private var tweet: Tweet?
    @State private var error: String?

    var body: some View {
        Group {
            if let tweet {
                TweetDetailView(tweet: tweet)
            } else if let error {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load tweet",
                    message: error
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            do {
                tweet = try await app.api.fetchTweet(hash: hash)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct NotifSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(TribeColor.chipBackground).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 180, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 120, height: 8)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}
