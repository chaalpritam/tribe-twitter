import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var app: AppState
    @State private var tasks: [TaskItem] = []
    @State private var filter: String = "open"
    @State private var loading = true
    @State private var error: String?

    private let filters = ["open", "claimed", "completed", "all"]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { f in
                            Button {
                                filter = f
                                load()
                            } label: {
                                Text(f.capitalized)
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(filter == f ? TribeColor.primary : TribeColor.chipBackground)
                                    )
                                    .foregroundStyle(filter == f ? Color.white : TribeColor.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if loading {
                    ForEach(0..<3, id: \.self) { _ in TaskSkeleton() }
                } else if let error {
                    EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't load tasks", message: error, action: ("Retry", load))
                        .padding(.horizontal, 16)
                } else if tasks.isEmpty {
                    EmptyStateView(symbol: "checkmark.seal", title: "No \(filter == "all" ? "" : filter) tasks", message: "Things people post for the network to pick up.")
                        .padding(.horizontal, 16)
                } else {
                    ForEach(tasks) { t in TaskCard(task: t).padding(.horizontal, 16) }
                }
            }
            .padding(.top, 6)
        }
        .background(TribeColor.pageBackground)
        .refreshable { await refresh() }
        .task { load() }
    }

    private func load() { Task { await refresh() } }

    @MainActor
    private func refresh() async {
        loading = tasks.isEmpty
        error = nil
        do {
            let status: String? = filter == "all" ? nil : filter
            tasks = try await app.api.fetchTasks(status: status)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct TaskCard: View {
    let task: TaskItem
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Pill(text: task.status, color: statusColor)
                    Spacer()
                    if let r = task.rewardText, !r.isEmpty {
                        Text(r)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TribeColor.accentEmerald)
                    }
                }
                Text(task.title)
                    .font(.system(size: 16, weight: .bold))
                if let d = task.description, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 13))
                        .foregroundStyle(TribeColor.textSecondary)
                        .lineLimit(3)
                }
                Text("by TID #\(task.creatorTid)")
                    .font(.system(size: 11))
                    .foregroundStyle(TribeColor.textTertiary)
            }
        }
    }

    private var statusColor: Color {
        switch task.status {
        case "open": return TribeColor.accentIndigo
        case "claimed": return TribeColor.accentAmber
        case "completed": return TribeColor.accentEmerald
        default: return TribeColor.textSecondary
        }
    }
}

private struct TaskSkeleton: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 80, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(maxWidth: .infinity).frame(height: 16)
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 200, height: 10)
            }
        }
        .padding(.horizontal, 16)
    }
}
