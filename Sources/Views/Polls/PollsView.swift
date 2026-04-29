import SwiftUI

struct PollsView: View {
    @EnvironmentObject private var app: AppState
    @State private var polls: [Poll] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if loading {
                    ForEach(0..<3, id: \.self) { _ in PollSkeleton() }
                } else if let error {
                    EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't load polls", message: error, action: ("Retry", load))
                        .padding(.horizontal, 16)
                } else if polls.isEmpty {
                    EmptyStateView(symbol: "chart.bar", title: "No polls yet", message: "Polls give the network a quick vote. Create one from tribe-app.")
                        .padding(.horizontal, 16)
                } else {
                    ForEach(polls) { p in
                        PollCard(poll: p).padding(.horizontal, 16)
                    }
                }
            }
        }
        .background(TribeColor.pageBackground)
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
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Pill(text: "Community poll", color: TribeColor.accentIndigo)
                    Spacer()
                    if let exp = poll.expiresAt {
                        Text(closesText(exp))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TribeColor.textSecondary)
                    }
                }
                Text(poll.question)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.2)
                VStack(spacing: 6) {
                    ForEach(poll.options.indices, id: \.self) { i in
                        HStack {
                            Text(poll.options[i])
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(TribeColor.cardStroke, lineWidth: 1)
                        )
                    }
                }
                Text("\(poll.totalVotes ?? 0) votes · by TID #\(poll.creatorTid)")
                    .font(.system(size: 11))
                    .foregroundStyle(TribeColor.textTertiary)
            }
        }
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
        Card {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 120, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(maxWidth: .infinity).frame(height: 16)
                RoundedRectangle(cornerRadius: 14).fill(TribeColor.chipBackground).frame(height: 36)
                RoundedRectangle(cornerRadius: 14).fill(TribeColor.chipBackground).frame(height: 36)
            }
        }
        .padding(.horizontal, 16)
    }
}
