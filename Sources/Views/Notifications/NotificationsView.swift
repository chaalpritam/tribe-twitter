import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var app: AppState
    @State private var rows: [TribeNotification] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader("Notifications", subtitle: "Replies, tips, RSVPs, and more")

                if app.myTID == nil {
                    EmptyStateView(
                        symbol: "person.crop.circle.badge.exclamationmark",
                        title: "Sign in required",
                        body: "Set your TID in Settings to see notifications addressed to you."
                    )
                    .padding(.horizontal, 16)
                } else if loading {
                    LazyVStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in NotifSkeleton() }
                    }
                } else if let error {
                    EmptyStateView(
                        symbol: "wifi.exclamationmark",
                        title: "Couldn't load notifications",
                        body: error,
                        action: ("Retry", load)
                    )
                    .padding(.horizontal, 16)
                } else if rows.isEmpty {
                    EmptyStateView(
                        symbol: "bell",
                        title: "All caught up",
                        body: "Replies, reactions, tips, RSVPs, and other activity will appear here."
                    )
                    .padding(.horizontal, 16)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { row in
                            NotifRow(row: row)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: TribeMetrics.bottomNavReservedHeight)
            }
        }
        .background(TribeColor.pageBackground)
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
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct NotifRow: View {
    let row: TribeNotification

    var body: some View {
        Card(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(TribeColor.chipBackground)
                    Image(systemName: row.type.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TribeColor.textPrimary)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("TID #\(row.actorTid) \(row.type.label)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TribeColor.textPrimary)
                    if let preview = row.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 12))
                            .foregroundStyle(TribeColor.textSecondary)
                            .lineLimit(2)
                    }
                    Text(RelativeTime.short(row.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(TribeColor.textTertiary)
                }
                Spacer()
            }
        }
    }
}

private struct NotifSkeleton: View {
    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Circle().fill(TribeColor.chipBackground).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 180, height: 10)
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 120, height: 8)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }
}
