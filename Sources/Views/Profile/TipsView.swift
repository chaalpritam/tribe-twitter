import SwiftUI
import TribeCore

/// On-chain tip history pushed from the profile ⋯ menu. Mirrors the
/// hub's tip-registry rows for the signed-in user — Received and
/// Sent in a segmented filter, each row deep-linking to the Solana
/// explorer for the settling transaction.
///
/// Off-chain TIP_ADD envelopes (the ones the iOS app itself can
/// publish) live in WalletView; this screen is the L1-settled
/// counterpart so the user can audit what actually moved on-chain.
struct TipsView: View {
    @EnvironmentObject private var app: AppState

    @State private var received: [OnchainTip] = []
    @State private var sent: [OnchainTip] = []
    @State private var loading = true
    @State private var error: String?
    @State private var filter: Filter = .received

    enum Filter: String, CaseIterable, Identifiable {
        case received = "Received"
        case sent = "Sent"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                summaryRow

                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if loading && currentList.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        TipSkeletonRow()
                            .padding(.horizontal, 16)
                    }
                } else if let error, currentList.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(TribeColor.accentRose)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if currentList.isEmpty {
                    emptyState
                        .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 8) {
                        ForEach(currentList) { tip in
                            TipRow(tip: tip, role: filter == .received ? .received : .sent)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(TribeColor.pageBackground)
        .navigationTitle("Tips")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { load() }
    }

    private var currentList: [OnchainTip] {
        switch filter {
        case .received: return received
        case .sent: return sent
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 10) {
            summaryTile(
                value: "\(received.count)",
                amount: totalReceivedSol,
                label: "Received",
                symbol: "arrow.down.left",
                tint: TribeColor.accentEmerald
            )
            summaryTile(
                value: "\(sent.count)",
                amount: totalSentSol,
                label: "Sent",
                symbol: "arrow.up.right",
                tint: TribeColor.accentAmber
            )
        }
        .padding(.horizontal, 16)
    }

    private func summaryTile(
        value: String,
        amount: String,
        label: String,
        symbol: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 26, height: 26)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("tips")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(amount) SOL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.4)
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

    private var totalReceivedSol: String {
        let lamports = received.reduce(0) { $0 + $1.amount }
        return formatSol(lamports)
    }

    private var totalSentSol: String {
        let lamports = sent.reduce(0) { $0 + $1.amount }
        return formatSol(lamports)
    }

    private func formatSol(_ lamports: Int64) -> String {
        let sol = Double(lamports) / 1_000_000_000
        return String(format: "%g", sol)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dollarsign.circle")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(filter == .received ? "No tips received yet" : "No tips sent yet")
                .font(.subheadline.weight(.semibold))
            Text(filter == .received
                 ? "On-chain tips you've received from other users will show up here."
                 : "On-chain tips you've sent will show up here once they settle on Solana.")
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

    // MARK: - Loading

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard let tid = app.myTID else { loading = false; return }
        loading = received.isEmpty && sent.isEmpty
        error = nil
        async let r = (try? await app.api.fetchOnchainTipsReceived(tid)) ?? []
        async let s = (try? await app.api.fetchOnchainTipsSent(tid)) ?? []
        let (rr, ss) = await (r, s)
        received = rr
        sent = ss
        loading = false
    }
}

// MARK: - Row

private struct TipRow: View {
    enum Role { case received, sent }

    let tip: OnchainTip
    let role: Role

    private var counterpartyTID: String {
        role == .received ? tip.senderTid : tip.recipientTid
    }

    private var counterpartyTitle: String {
        if let u = tip.counterpartyUsername, !u.isEmpty {
            return "@\(u).tribe"
        }
        return "TID #\(counterpartyTID)"
    }

    private var counterpartyInitial: String {
        if let u = tip.counterpartyUsername, let first = u.first {
            return String(first).uppercased()
        }
        return String(counterpartyTID.prefix(1))
    }

    private var explorerURL: URL? {
        URL(string: "https://explorer.solana.com/tx/\(tip.txSignature)?cluster=\(Config.solanaCluster)")
    }

    var body: some View {
        HStack(spacing: 12) {
            UserAvatar(
                tid: counterpartyTID,
                initial: counterpartyInitial,
                size: 40,
                seed: tip.counterpartyUsername ?? counterpartyTID
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(role == .received ? "From" : "To")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(counterpartyTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(role == .received ? "+" : "−")\(tip.formattedSol) SOL")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(role == .received ? TribeColor.accentEmerald : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(RelativeTime.short(tip.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let url = explorerURL {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                                .foregroundStyle(TribeColor.brand)
                        }
                    }
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
}

private struct TipSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 60, height: 9)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 130, height: 11)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 80, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 50, height: 9)
            }
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
