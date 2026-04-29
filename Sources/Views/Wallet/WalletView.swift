import SwiftUI
import UIKit

/// Wallet tab. The send path is intentionally read-only here —
/// publishing a TIP_ADD envelope and a Solana on-chain transfer
/// both need crypto helpers ported from tribe-app, which is a
/// separate workstream. Receive (address + QR) and recent tip
/// activity work end-to-end against the existing hub.
struct WalletView: View {
    @EnvironmentObject private var app: AppState
    @State private var sent: [Tip] = []
    @State private var received: [Tip] = []
    @State private var loading = true
    @State private var showingReceive = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader("Wallet", subtitle: "Receive and view tip activity")

                balanceCard
                    .padding(.horizontal, 16)

                Text("Recent activity")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(TribeColor.textSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 22)
                    .padding(.top, 4)

                activityList

                Spacer(minLength: TribeMetrics.bottomNavReservedHeight)
            }
        }
        .background(TribeColor.pageBackground)
        .refreshable { await refresh() }
        .task { load() }
        .sheet(isPresented: $showingReceive) {
            if let tid = app.myTID {
                NavigationStack {
                    ReceiveSheet(
                        tid: tid,
                        username: app.myUsername,
                        address: app.walletAddress
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingReceive = false }
                        }
                    }
                }
            }
        }
    }

    private var balanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tribe identity")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(TribeColor.textSecondary)

                if let tid = app.myTID {
                    Text(app.myUsername.map { "\($0).tribe" } ?? "TID #\(tid)")
                        .font(.system(size: 24, weight: .black))
                        .tracking(-0.4)
                    Text("TID #\(tid)")
                        .font(.system(size: 12))
                        .foregroundStyle(TribeColor.textSecondary)
                } else {
                    Text("No TID set")
                        .font(.system(size: 18, weight: .bold))
                    Text("Open Settings and enter your TID to enable wallet features.")
                        .font(.system(size: 12))
                        .foregroundStyle(TribeColor.textSecondary)
                }

                HStack(spacing: 8) {
                    Button {
                        // Send is read-only — show a notice instead of attempting.
                    } label: {
                        Text("Send").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(true)

                    Button {
                        showingReceive = true
                    } label: {
                        Text("Receive").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WalletPrimaryStyle())
                    .disabled(app.myTID == nil)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var activityList: some View {
        if loading {
            VStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Card(padding: 12) {
                        HStack {
                            Circle().fill(TribeColor.chipBackground).frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 140, height: 10)
                                RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 90, height: 8)
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        } else if app.myTID == nil {
            EmptyStateView(symbol: "wallet.pass", title: "Sign in to see activity")
                .padding(.horizontal, 16)
        } else if combined.isEmpty {
            EmptyStateView(symbol: "tray", title: "No tip activity yet", message: "Tips sent or received will appear here.")
                .padding(.horizontal, 16)
        } else {
            VStack(spacing: 6) {
                ForEach(combined, id: \.id) { row in
                    ActivityRow(direction: row.direction, tip: row.tip)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    fileprivate struct ActivityItem: Identifiable {
        let direction: Direction
        let tip: Tip
        var id: String { "\(direction.rawValue)-\(tip.id)" }
        enum Direction: String { case sent, received }
    }

    private var combined: [ActivityItem] {
        let s = sent.map { ActivityItem(direction: .sent, tip: $0) }
        let r = received.map { ActivityItem(direction: .received, tip: $0) }
        return (s + r).sorted { $0.tip.sentAt > $1.tip.sentAt }
    }

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard let tid = app.myTID else { loading = false; return }
        loading = sent.isEmpty && received.isEmpty
        async let s = (try? await app.api.fetchTipsSent(tid)) ?? []
        async let r = (try? await app.api.fetchTipsReceived(tid)) ?? []
        let (ss, rr) = await (s, r)
        self.sent = ss
        self.received = rr
        loading = false
    }
}

private struct ActivityRow: View {
    let direction: WalletView.ActivityItem.Direction
    let tip: Tip

    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(TribeColor.chipBackground)
                    Image(systemName: direction == .sent ? "arrow.up.right" : "arrow.down.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(direction == .sent ? TribeColor.textPrimary : TribeColor.accentEmerald)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(direction.rawValue.capitalized) \(direction == .sent ? "to" : "from") TID #\(direction == .sent ? tip.recipientTid : tip.senderTid)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(tip.sentAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(TribeColor.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(direction == .sent ? "−" : "+")\(formattedAmount) \(tip.currency)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(direction == .received ? TribeColor.accentEmerald : TribeColor.textPrimary)
                    if let sig = tip.txSignature {
                        Link("Tx ↗", destination: explorerURL(sig))
                            .font(.system(size: 10))
                            .foregroundStyle(TribeColor.accentIndigo)
                    }
                }
            }
        }
    }

    private var formattedAmount: String {
        let n = NSDecimalNumber(decimal: tip.amount).doubleValue
        return String(format: "%g", n)
    }

    private func explorerURL(_ sig: String) -> URL {
        URL(string: "https://explorer.solana.com/tx/\(sig)?cluster=\(Config.solanaCluster)")!
    }
}

private struct ReceiveSheet: View {
    let tid: String
    let username: String?
    let address: String?

    @State private var copyToast = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Receive")
                    .font(.system(size: 24, weight: .black))
                    .tracking(-0.4)
                    .padding(.top, 16)

                Card {
                    VStack(spacing: 16) {
                        QRCodeView(value: address ?? "TID:\(tid)", size: 220)
                        VStack(spacing: 4) {
                            Text(username.map { "\($0).tribe" } ?? "TID #\(tid)")
                                .font(.system(size: 17, weight: .bold))
                            Text("TID #\(tid)")
                                .font(.system(size: 12))
                                .foregroundStyle(TribeColor.textSecondary)
                        }
                        if let a = address {
                            Text(a)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(TribeColor.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(TribeColor.chipBackground)
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("Set your wallet address in Settings to share a Solana QR.")
                                .font(.system(size: 11))
                                .foregroundStyle(TribeColor.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 16)

                if let a = address {
                    Button {
                        UIPasteboard.general.string = a
                        copyToast = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            await MainActor.run { copyToast = false }
                        }
                    } label: {
                        Label(copyToast ? "Copied!" : "Copy address", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WalletPrimaryStyle())
                    .padding(.horizontal, 16)
                }

                Text("Senders inside Tribe can use your TID instead of pasting the full address.")
                    .font(.system(size: 11))
                    .foregroundStyle(TribeColor.textTertiary)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 32)
        }
        .background(TribeColor.pageBackground)
    }
}

struct WalletPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(TribeColor.primary).opacity(configuration.isPressed ? 0.85 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(TribeColor.textPrimary)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(TribeColor.chipBackground)
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
    }
}
