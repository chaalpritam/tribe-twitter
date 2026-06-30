import SwiftUI
import TribeCore
import UIKit

/// Wallet hub. Hero card with the user's identity + send / receive
/// shortcuts, three stat tiles summarizing tip activity at a glance,
/// a segmented filter, and an activity feed. The send path still
/// publishes a TIP_ADD envelope (not an on-chain transfer) since the
/// iOS app doesn't hold the user's Solana custody key — see
/// SendTipSheet for the explainer.
struct WalletView: View {
    @EnvironmentObject private var app: AppState
    @State private var sent: [Tip] = []
    @State private var received: [Tip] = []
    @State private var loading = true
    @State private var showingReceive = false
    @State private var showingSend = false
    @State private var filter: ActivityFilter = .all

    enum ActivityFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case received = "Received"
        case sent = "Sent"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                heroCard
                statsRow
                if app.myTID != nil {
                    activitySection
                }
            }
            .padding(.vertical, 16)
        }
        .background(TribeColor.pageBackground)
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wallet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .textCase(.uppercase)
                    .tracking(0.5)

                if let tid = app.myTID {
                    Text(app.myUsername.map { "@\($0).tribe" } ?? "TID #\(tid)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                    Text("TID #\(tid)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    Text("Not signed in")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Open Settings and enter your TID to enable wallet features.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let address = app.walletAddress, !address.isEmpty {
                Label(short(address), systemImage: "wallet.pass")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.18)))
            }

            HStack(spacing: 10) {
                Button {
                    showingSend = true
                } label: {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TribeColor.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(.white))
                }
                .disabled(app.appKey == nil)

                Button {
                    showingReceive = true
                } label: {
                    Label("Receive", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(.white.opacity(0.22)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                }
                .disabled(app.myTID == nil)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TribeColor.brandGradient)
        )
        .shadow(color: TribeColor.brand.opacity(0.3), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 16)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(
                value: "\(received.count)",
                label: "Received",
                symbol: "arrow.down.left",
                tint: TribeColor.accentEmerald
            )
            statTile(
                value: "\(sent.count)",
                label: "Sent",
                symbol: "arrow.up.right",
                tint: TribeColor.brand
            )
            statTile(
                value: formattedTotalReceived,
                label: "Net SOL",
                symbol: "dollarsign.circle.fill",
                tint: TribeColor.accentAmber
            )
        }
        .padding(.horizontal, 16)
    }

    private func statTile(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 26, height: 26)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    // MARK: - Activity

    @ViewBuilder
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity")
                    .font(.title3.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 16)

            Picker("Filter", selection: $filter) {
                ForEach(ActivityFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if loading && combined.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    ActivitySkeleton()
                        .padding(.horizontal, 16)
                }
            } else if filtered.isEmpty {
                emptyActivity
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(filtered) { row in
                        WalletActivityRow(direction: row.direction, tip: row.tip)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private var emptyActivity: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No \(filter == .all ? "tip" : filter.rawValue.lowercased()) activity")
                .font(.subheadline.weight(.semibold))
            Text("Tips you send or receive will show up here.")
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

    // MARK: - Activity model

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

    private var filtered: [ActivityItem] {
        switch filter {
        case .all: return combined
        case .received: return combined.filter { $0.direction == .received }
        case .sent: return combined.filter { $0.direction == .sent }
        }
    }

    private var formattedTotalReceived: String {
        // Net SOL (received - sent), constrained to SOL amounts. Other
        // currencies still count for the row counters but skip the
        // net total since cross-currency math isn't sensible.
        let recvSol = received
            .filter { $0.currency.uppercased() == "SOL" }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let sentSol = sent
            .filter { $0.currency.uppercased() == "SOL" }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let net = recvSol - sentSol
        let value = NSDecimalNumber(decimal: net).doubleValue
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%g", value))"
    }

    private func short(_ s: String) -> String {
        guard s.count > 10 else { return s }
        return "\(s.prefix(5))…\(s.suffix(5))"
    }

    // MARK: - Loading

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

// MARK: - Rows

private struct WalletActivityRow: View {
    @EnvironmentObject private var app: AppState
    let direction: WalletView.ActivityItem.Direction
    let tip: Tip

    private var counterpartyTID: String {
        direction == .sent ? tip.recipientTid : tip.senderTid
    }

    private var counterpartyInitial: String {
        String(counterpartyTID.prefix(1))
    }

    var body: some View {
        HStack(spacing: 12) {
            UserAvatar(
                tid: counterpartyTID,
                initial: counterpartyInitial,
                size: 40,
                seed: counterpartyTID
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(direction == .received ? "Received from" : "Sent to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("TID #\(counterpartyTID)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(direction == .sent ? "−" : "+")\(formattedAmount) \(tip.currency)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(direction == .received ? TribeColor.accentEmerald : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(RelativeTime.short(tip.sentAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let sig = tip.txSignature {
                        Link(destination: explorerURL(sig)) {
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

    private var formattedAmount: String {
        let n = NSDecimalNumber(decimal: tip.amount).doubleValue
        return String(format: "%g", n)
    }

    private func explorerURL(_ sig: String) -> URL {
        URL(string: "https://explorer.solana.com/tx/\(sig)?cluster=\(Config.solanaCluster)")!
    }
}

private struct ActivitySkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 90, height: 9)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 130, height: 11)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 70, height: 11)
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

// MARK: - Receive

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
                        Text(username.map { "@\($0).tribe" } ?? "TID #\(tid)")
                            .font(.title3.weight(.bold))
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
                        .fill(TribeColor.surface)
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
                    .tint(TribeColor.brand)
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
        .background(TribeColor.pageBackground)
    }
}

// MARK: - Send

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
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(TribeColor.accentRose)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if working { ProgressView().tint(.white) }
                            Text(working ? "Sending…" : "Send tip")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TribeColor.brand)
                    .controlSize(.large)
                    .disabled(!canSend)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .navigationTitle("Send tip")
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
