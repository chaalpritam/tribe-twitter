import SwiftUI

/// Off-chain-only tip flow. Publishes a signed TIP_ADD envelope so
/// the recipient's notifications + activity log surface the tip,
/// but skips the on-chain SOL transfer because iOS doesn't hold
/// the user's Solana custody key today.
///
/// Web's TipButton does the SOL transfer first and then publishes
/// this envelope as a follow-up; we ship the envelope-only half so
/// the social side of the tip is a one-tap action on iOS, and route
/// users to tribe-app when they actually want to move SOL.
struct TipSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let recipientTid: String
    let recipientName: String
    let tweetHash: String

    @State private var selected: Decimal = TipSheet.presets[1]
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false

    static let presets: [Decimal] = [0.001, 0.01, 0.05, 0.1]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tipping \(recipientName)")
                        .font(.headline)
                    Text("Off-chain receipt only — your Solana custody key isn't on this device, so no SOL actually moves. Open tribe-app on the web to send SOL on-chain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Amount") {
                    ForEach(Self.presets, id: \.self) { preset in
                        Button {
                            selected = preset
                        } label: {
                            HStack {
                                Text(format(preset) + " SOL")
                                    .font(.body.weight(.medium))
                                Spacer()
                                if selected == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if sent {
                    Section {
                        Label("Tip published", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if sending { ProgressView() }
                            Text(sending ? "Publishing…" : "Publish tip")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(sending || sent || app.appKey == nil || app.myTID == nil)
                }
            }
            .navigationTitle("Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func format(_ d: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: d as NSDecimalNumber) ?? "\(d)"
    }

    @MainActor
    private func send() async {
        guard let key = app.appKey, let myTID = app.myTID else { return }
        sending = true
        error = nil
        defer { sending = false }
        do {
            _ = try await app.api.publishTip(
                recipientTid: recipientTid,
                amount: selected,
                currency: "SOL",
                targetHash: tweetHash,
                txSignature: nil,
                as: key,
                tid: myTID
            )
            sent = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
