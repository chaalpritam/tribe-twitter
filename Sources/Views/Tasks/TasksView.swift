import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var app: AppState
    @State private var tasks: [TaskItem] = []
    @State private var filter: Filter = .open
    @State private var loading = true
    @State private var error: String?

    enum Filter: String, CaseIterable, Identifiable {
        case open, claimed, completed, all
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var apiValue: String? { self == .all ? nil : rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: filter) { _, _ in load() }

            Group {
                if loading && tasks.isEmpty {
                    List {
                        ForEach(0..<3, id: \.self) { _ in TaskSkeleton() }
                    }
                    .listStyle(.insetGrouped)
                } else if let error, tasks.isEmpty {
                    EmptyStateView(
                        symbol: "wifi.exclamationmark",
                        title: "Couldn't load tasks",
                        message: error,
                        action: ("Retry", load)
                    )
                } else if tasks.isEmpty {
                    EmptyStateView(
                        symbol: "checkmark.seal",
                        title: "No \(filter == .all ? "" : filter.rawValue) tasks",
                        message: "Things people post for the network to pick up."
                    )
                } else {
                    List(tasks) { task in
                        TaskRow(task: task)
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .refreshable { await refresh() }
        .task { load() }
    }

    private func load() { Task { await refresh() } }

    @MainActor
    private func refresh() async {
        loading = tasks.isEmpty
        error = nil
        do {
            tasks = try await app.api.fetchTasks(status: filter.apiValue)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct TaskRow: View {
    let task: TaskItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Pill(text: task.status, color: statusColor)
                Spacer()
                if let r = task.rewardText, !r.isEmpty {
                    Text(r)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            Text(task.title)
                .font(.headline)
            if let d = task.description, !d.isEmpty {
                Text(d)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text("by TID #\(task.creatorTid)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch task.status {
        case "open": return .indigo
        case "claimed": return .orange
        case "completed": return .green
        default: return .secondary
        }
    }
}

private struct TaskSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 80, height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 16)
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 200, height: 10)
        }
        .padding(.vertical, 6)
        .redacted(reason: .placeholder)
    }
}
