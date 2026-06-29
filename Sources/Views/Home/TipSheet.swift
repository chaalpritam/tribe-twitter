import SwiftUI

/// Off-chain-only tip flow. Publishes a signed TIP_ADD envelope so
/// the recipient's notifications + activity log surface the tip,
/// but skips the on-chain SOL transfer because iOS doesn't hold
/// the user's Solana custody key today.
///
/// Web's TipButton does the SOL transfer first and then publishes
/// this envelope as a follow-up; we ship the envelope-only half so
/// the social side of the tip is a one-tap action on iOS, and route
/// users to tribe-twitter-app when they actually want to move SOL.
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
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(TribeColor.accentAmber.opacity(0.18))
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.title)
                                .foregroundStyle(TribeColor.accentAmber)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tipping \(recipientName)")
                                .font(.headline)
                            Text("Off-chain receipt")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Your Solana custody key isn't on this device, so no SOL actually moves. Open tribe-twitter-app on the web to send SOL on-chain.")
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
                                    .monospacedDigit()
                                Spacer()
                                if selected == preset {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(TribeColor.accentAmber)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(TribeColor.accentRose)
                            .font(.footnote)
                    }
                }

                if sent {
                    Section {
                        Label("Tip published", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(TribeColor.accentEmerald)
                    }
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if sending { ProgressView().tint(.white) }
                            Text(sending ? "Publishing…" : "Publish tip")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TribeColor.accentAmber)
                    .controlSize(.large)
                    .disabled(sending || sent || app.appKey == nil || app.myTID == nil)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
