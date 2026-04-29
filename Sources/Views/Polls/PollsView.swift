import SwiftUI

struct PollsView: View {
    @EnvironmentObject private var app: AppState
    @State private var polls: [Poll] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading && polls.isEmpty {
                List {
                    ForEach(0..<3, id: \.self) { _ in PollSkeleton() }
                }
                .listStyle(.insetGrouped)
            } else if let error, polls.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load polls",
                    message: error,
                    action: ("Retry", load)
                )
            } else if polls.isEmpty {
                EmptyStateView(
                    symbol: "chart.bar",
                    title: "No polls yet",
                    message: "Polls give the network a quick vote. Create one from tribe-app."
                )
            } else {
                List(polls) { poll in
                    PollCard(poll: poll)
                }
                .listStyle(.insetGrouped)
            }
        }
        .refreshable { await refresh() }
        .task { load() }
    }

    private func load() { Task { await refresh() } }

    @MainActor
    private func refresh() async {
        loading = polls.isEmpty
        error = nil
        do { polls = try await app.api.fetchPolls() } catch { self.error = error.localizedDescription }
        loading = false
    }
}

private struct PollCard: View {
    let poll: Poll
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Pill(text: "Community poll", color: .indigo)
                Spacer()
                if let exp = poll.expiresAt {
                    Text(closesText(exp))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(poll.question)
                .font(.headline)
            VStack(spacing: 6) {
                ForEach(poll.options.indices, id: \.self) { i in
                    HStack {
                        Text(poll.options[i])
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(TribeColor.cardStroke, lineWidth: 0.5)
                    )
                }
            }
            Text("\(poll.totalVotes ?? 0) votes · by TID #\(poll.creatorTid)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func closesText(_ d: Date) -> String {
        let now = Date()
        if d < now { return "Closed" }
        let diff = Int(d.timeIntervalSince(now))
        if diff < 3600 { return "\(diff/60)m left" }
        if diff < 86400 { return "\(diff/3600)h left" }
        return "\(diff/86400)d left"
    }
}

private struct PollSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 120, height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 16)
            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)).frame(height: 36)
            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)).frame(height: 36)
        }
        .padding(.vertical, 6)
        .redacted(reason: .placeholder)
    }
}
