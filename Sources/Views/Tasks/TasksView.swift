import SwiftUI
import TribeCore

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
    @EnvironmentObject private var app: AppState
    let task: TaskItem

    @State private var localStatus: String
    @State private var working = false
    @State private var error: String?

    init(task: TaskItem) {
        self.task = task
        _localStatus = State(initialValue: task.status)
    }

    private var canClaim: Bool {
        localStatus == "open" && app.appKey != nil && app.myTID != nil
    }

    private var canComplete: Bool {
        guard let myTID = app.myTID else { return false }
        return localStatus == "claimed" && task.claimedByTid == myTID && app.appKey != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Pill(text: localStatus, color: statusColor)
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
            HStack {
                Text("by TID #\(task.creatorTid)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if canClaim {
                    Button("Claim") { Task { await claim() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(working)
                } else if canComplete {
                    Button("Mark complete") { Task { await complete() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(working)
                } else if working {
                    ProgressView().controlSize(.mini)
                }
            }
            if let error {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch localStatus {
        case "open": return .indigo
        case "claimed": return .orange
        case "completed": return .green
        default: return .secondary
        }
    }

    private func claim() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        let previous = localStatus
        localStatus = "claimed"
        working = true
        defer { working = false }
        do {
            _ = try await app.api.claimTask(taskId: task.id, as: key, tid: tid)
            error = nil
        } catch {
            localStatus = previous
            self.error = error.localizedDescription
        }
    }

    private func complete() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        let previous = localStatus
        localStatus = "completed"
        working = true
        defer { working = false }
        do {
            _ = try await app.api.completeTask(taskId: task.id, as: key, tid: tid)
            error = nil
        } catch {
            localStatus = previous
            self.error = error.localizedDescription
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
