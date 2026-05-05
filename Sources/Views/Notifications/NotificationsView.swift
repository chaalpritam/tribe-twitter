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
                List(rows) { row in
                    NotifRow(row: row)
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
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct NotifRow: View {
    let row: TribeNotification

    var body: some View {
        NavigationLink {
            ProfileView(tid: row.actorTid)
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
                    Text("\(actorDisplay) \(row.type.label)")
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
