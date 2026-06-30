import SwiftUI
import TribeCore

/// Account transparency log mirroring tribe-twitter-app's /activity page.
/// Top: three stat tiles (total, onchain, signed-offchain) + a
/// segmented filter. Body: rows grouped by date bucket (Today /
/// Yesterday / This week / This month / Older), each leading with
/// a type-colored icon, the verb, peer + preview, and an explorer
/// link if the action settled on Solana.
struct ActivityView: View {
    @EnvironmentObject private var app: AppState
    @State private var rows: [ActivityRow] = []
    @State private var filter: Filter = .all
    @State private var loading = true
    @State private var error: String?

    enum Filter: String, CaseIterable, Identifiable {
        case all, onchain, offchain
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .onchain: return "On-chain"
            case .offchain: return "Signed"
            }
        }
    }

    private var filtered: [ActivityRow] {
        switch filter {
        case .all: return rows
        case .onchain: return rows.filter { $0.type.isOnChain }
        case .offchain: return rows.filter { !$0.type.isOnChain }
        }
    }

    private var onChainCount: Int { rows.filter { $0.type.isOnChain }.count }
    private var offChainCount: Int { rows.count - onChainCount }

    var body: some View {
        Group {
            if app.myTID == nil {
                EmptyStateView(
                    symbol: "person.crop.circle.badge.exclamationmark",
                    title: "Sign in required",
                    message: "Set your TID in Settings to see your account's activity log."
                )
            } else if loading && rows.isEmpty {
                loadingState
            } else if let error, rows.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load activity",
                    message: error,
                    action: ("Retry", load)
                )
            } else {
                content
            }
        }
        .background(TribeColor.pageBackground)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { load() }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                statsRow
                filterRow

                if filtered.isEmpty {
                    emptyState
                        .padding(.horizontal, 16)
                } else {
                    ForEach(grouped, id: \.bucket) { group in
                        Section {
                            VStack(spacing: 8) {
                                ForEach(group.rows) { row in
                                    ActivityCard(row: row)
                                        .padding(.horizontal, 16)
                                }
                            }
                        } header: {
                            sectionHeader(group.bucket.title)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(
                value: "\(rows.count)",
                label: "Total",
                symbol: "rectangle.stack.fill",
                tint: TribeColor.brand
            )
            statTile(
                value: "\(onChainCount)",
                label: "On-chain",
                symbol: "link",
                tint: TribeColor.accentEmerald
            )
            statTile(
                value: "\(offChainCount)",
                label: "Signed",
                symbol: "signature",
                tint: TribeColor.accentIndigo
            )
        }
        .padding(.horizontal, 16)
    }

    private func statTile(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 26, height: 26)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TribeColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TribeColor.cardStroke.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Filter

    private var filterRow: some View {
        Picker("Filter", selection: $filter) {
            ForEach(Filter.allCases) { f in
                Text(f.label).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    // MARK: - Grouping

    private struct ActivityGroup: Hashable {
        let bucket: Bucket
        let rows: [ActivityRow]
    }

    private enum Bucket: String, Hashable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This week"
        case thisMonth = "This month"
        case older = "Older"

        var title: String { rawValue }

        static func bucket(for date: Date, now: Date = Date()) -> Bucket {
            let cal = Calendar.current
            if cal.isDateInToday(date) { return .today }
            if cal.isDateInYesterday(date) { return .yesterday }
            if cal.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return .thisWeek }
            if cal.isDate(date, equalTo: now, toGranularity: .month) { return .thisMonth }
            return .older
        }
    }

    private var grouped: [ActivityGroup] {
        let now = Date()
        let buckets: [Bucket] = [.today, .yesterday, .thisWeek, .thisMonth, .older]
        var byBucket: [Bucket: [ActivityRow]] = [:]
        for row in filtered {
            let b = Bucket.bucket(for: row.timestamp, now: now)
            byBucket[b, default: []].append(row)
        }
        return buckets.compactMap { b in
            guard let rows = byBucket[b], !rows.isEmpty else { return nil }
            return ActivityGroup(bucket: b, rows: rows)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(TribeColor.pageBackground)
    }

    // MARK: - Empty / loading

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: 16) {
                statsRow.redacted(reason: .placeholder)
                filterRow
                ForEach(0..<4, id: \.self) { _ in
                    ActivitySkeleton()
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(emptyTitle)
                .font(.subheadline.weight(.semibold))
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TribeColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TribeColor.cardStroke.opacity(0.4), lineWidth: 0.5)
        )
    }

    private var emptyTitle: String {
        switch filter {
        case .onchain: return "No on-chain activity yet"
        case .offchain: return "No signed envelopes yet"
        case .all: return "No activity yet"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .onchain:
            return "Follow someone or send a tip to start your on-chain history."
        case .offchain:
            return "Post a tweet, like something, or send a DM."
        case .all:
            return "Activity will appear here as you use the protocol."
        }
    }

    // MARK: - Loading

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard let tid = app.myTID else { loading = false; return }
        loading = rows.isEmpty
        error = nil
        do {
            rows = try await app.api.fetchActivity(tid)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Row card

private struct ActivityCard: View {
    let row: ActivityRow

    private var explorerURL: URL? {
        guard let sig = row.txSignature else { return nil }
        return URL(string: "https://explorer.solana.com/tx/\(sig)?cluster=devnet")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(typeTint.opacity(0.15))
                Image(systemName: typeSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(typeTint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.type.verb)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(RelativeTime.short(row.timestamp))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let preview = row.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if row.type.isOnChain {
                        miniChip("On-chain", tint: TribeColor.accentEmerald)
                    } else {
                        miniChip("Signed", tint: TribeColor.accentIndigo)
                    }
                    if let peer = row.peerTid {
                        NavigationLink {
                            ProfileView(tid: peer)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "at")
                                    .font(.caption2.weight(.semibold))
                                Text("TID #\(peer)")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(TribeColor.brand)
                        }
                        .buttonStyle(.plain)
                    }
                    if let url = explorerURL {
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption2.weight(.semibold))
                                Text("Tx")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(TribeColor.accentEmerald)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TribeColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TribeColor.cardStroke.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func miniChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .tracking(0.3)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var typeSymbol: String {
        switch row.type {
        case .tidRegistered: return "person.badge.key.fill"
        case .tweet: return "text.bubble.fill"
        case .tweetReply: return "arrowshape.turn.up.left.fill"
        case .reactionLike: return "heart.fill"
        case .reactionRecast: return "arrow.2.squarepath"
        case .bookmark: return "bookmark.fill"
        case .dmSent: return "envelope.fill"
        case .tipSent, .tipReceived: return "dollarsign.circle.fill"
        case .followPending, .followSettled: return "person.badge.plus"
        case .followFailed: return "person.badge.minus"
        case .unfollowPending, .unfollowSettled, .unfollowFailed:
            return "person.badge.minus"
        case .unknown: return "circle.dashed"
        }
    }

    private var typeTint: Color {
        switch row.type {
        case .tidRegistered: return TribeColor.brand
        case .tweet, .tweetReply: return TribeColor.brand
        case .reactionLike: return TribeColor.accentRose
        case .reactionRecast: return TribeColor.accentEmerald
        case .bookmark: return TribeColor.accentIndigo
        case .dmSent: return TribeColor.accentTeal
        case .tipSent, .tipReceived: return TribeColor.accentAmber
        case .followPending, .followSettled: return TribeColor.brand
        case .followFailed: return TribeColor.accentRose
        case .unfollowPending, .unfollowSettled: return .secondary
        case .unfollowFailed: return TribeColor.accentRose
        case .unknown: return .secondary
        }
    }
}

private struct ActivitySkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 160, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 9)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 90, height: 9)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TribeColor.surface)
        )
        .redacted(reason: .placeholder)
    }
}
