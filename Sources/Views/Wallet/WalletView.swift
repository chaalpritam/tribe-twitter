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
    @State private var showingSend = false

    var body: some View {
        List {
            Section {
                identityCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !combined.isEmpty {
                Section("Recent Activity") {
                    ForEach(combined, id: \.id) { row in
                        ActivityRow(direction: row.direction, tip: row.tip)
                    }
                }
            } else if !loading && app.myTID != nil {
                Section {
                    ContentUnavailableView(
                        "No tip activity yet",
                        systemImage: "tray",
                        description: Text("Tips sent or received will appear here.")
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Wallet")
        .refreshable { await refresh() }
        .task { load() }
        .sheet(isPresented: $showingSend) {
            SendTipSheet(onSent: {
                Task { await refresh() }
            })
            .environmentObject(app)
        }
        .sheet(isPresented: $showingReceive) {
            if let tid = app.myTID {
                NavigationStack {
                    ReceiveSheet(
                        tid: tid,
                        username: app.myUsername,
                        address: app.walletAddress
                    )
                    .navigationTitle("Receive")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingReceive = false }
                        }
                    }
                }
                .environmentObject(app)
            }
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tribe identity")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let tid = app.myTID {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.myUsername.map { "\($0).tribe" } ?? "TID #\(tid)")
                        .font(.title.weight(.bold))
                    Text("TID #\(tid)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No TID set")
                        .font(.title3.weight(.semibold))
                    Text("Open Settings and enter your TID to enable wallet features.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showingSend = true
                } label: {
                    Label("Send", systemImage: "arrow.up.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(app.appKey == nil)

                Button {
                    showingReceive = true
                } label: {
                    Label("Receive", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(app.myTID == nil)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(direction == .received ? Color.green.opacity(0.15) : Color(.tertiarySystemFill))
                Image(systemName: direction == .sent ? "arrow.up.right" : "arrow.down.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(direction == .sent ? Color.primary : .green)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(direction.rawValue.capitalized) \(direction == .sent ? "to" : "from") TID #\(direction == .sent ? tip.recipientTid : tip.senderTid)")
                    .font(.subheadline.weight(.medium))
                Text(tip.sentAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(direction == .sent ? "−" : "+")\(formattedAmount) \(tip.currency)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(direction == .received ? .green : .primary)
                if let sig = tip.txSignature {
                    Link(destination: explorerURL(sig)) {
                        Label("Tx", systemImage: "arrow.up.right.square")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
    @EnvironmentObject private var app: AppState
    let tid: String
    let username: String?
    let address: String?

    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    QRCodeView(value: address ?? "TID:\(tid)", size: 220)
                    VStack(spacing: 4) {
                        Text(username.map { "\($0).tribe" } ?? "TID #\(tid)")
                            .font(.title3.weight(.semibold))
                        Text("TID #\(tid)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let a = address {
                        Text(a)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Set your wallet address in Settings to share a Solana QR.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .padding(.horizontal, 16)

                if let a = address {
                    Button {
                        UIPasteboard.general.string = a
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            await MainActor.run { copied = false }
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 16)
                }

                Text("Senders inside Tribe can use your TID instead of pasting the full address.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct SendTipSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onSent: (() -> Void)?

    @State private var recipientTid: String = ""
    @State private var amount: String = ""
    @State private var currency: String = "SOL"
    @State private var working = false
    @State private var error: String?

    private var amountDecimal: Decimal? {
        let trimmed = amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let d = Decimal(string: trimmed), d > 0 else { return nil }
        return d
    }

    private var canSend: Bool {
        !working
            && Int64(recipientTid.trimmingCharacters(in: .whitespaces)) != nil
            && amountDecimal != nil
            && app.appKey != nil
            && app.myTID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Recipient TID", text: $recipientTid)
                        .keyboardType(.numberPad)
                } header: { Text("Recipient") }

                Section {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        Text("SOL").tag("SOL")
                        Text("USDC").tag("USDC")
                        Text("USD").tag("USD")
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    Text("This publishes a TIP_ADD envelope to the hub. Settling tips on Solana through the tip-registry program is a separate flow that needs Solana mobile / WalletConnect integration.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if working { ProgressView() }
                            Text(working ? "Sending…" : "Send tip")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSend)
                }
            }
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func send() async {
        guard let key = app.appKey,
              let tid = app.myTID,
              let value = amountDecimal,
              !working else { return }
        let recipient = recipientTid.trimmingCharacters(in: .whitespaces)
        working = true
        defer { working = false }
        do {
            _ = try await app.api.publishTip(
                recipientTid: recipient,
                amount: value,
                currency: currency,
                as: key,
                tid: tid
            )
            onSent?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
