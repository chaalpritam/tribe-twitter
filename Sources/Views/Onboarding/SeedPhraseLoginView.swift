import SwiftUI
import TribeCore

/// Two-stage seed-phrase sign-in:
///   1. Paste 12 / 24-word BIP39 mnemonic → derive Solana wallet at
///      m/44'/501'/0'/0' → ask the hub which TID owns that wallet.
///   2. Show the resolved TID + username and ask for the app-key seed
///      separately (the protocol's app-key is *not* derived from the
///      same phrase — it's an on-chain-registered ed25519 keypair
///      that lives in tribe-app's localStorage).
///
/// The "import a backup file" path is strictly better when the user
/// has one, since it bundles app-key + dm-key + wallet in a single
/// password-protected file. This view is the partial recovery path
/// for users who only kept the seed phrase.
struct SeedPhraseLoginView: View {
    @EnvironmentObject private var app: AppState

    @State private var phraseInput: String = ""
    @State private var resolving = false
    @State private var resolved: ResolvedWallet?
    @State private var appKeyInput: String = ""
    @State private var adopting = false
    @State private var error: String?

    private struct ResolvedWallet: Equatable {
        let address: String
        let user: User
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $phraseInput)
                    .frame(minHeight: 96)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            } header: {
                Text("Seed phrase")
            } footer: {
                Text("Paste your 12 or 24 word BIP39 phrase. Same derivation Phantom and Solflare use (m/44'/501'/0'/0'), so phrases from those wallets resolve to the same Solana address here.")
            }

            if resolved == nil {
                Section {
                    Button {
                        Task { await resolve() }
                    } label: {
                        HStack {
                            if resolving { ProgressView() }
                            Text(resolving ? "Looking up TID…" : "Continue")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(resolving || phraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let resolved {
                Section {
                    LabeledContent("Wallet") {
                        Text(short(resolved.address))
                            .font(.system(.footnote, design: .monospaced))
                    }
                    LabeledContent("TID", value: resolved.user.tid)
                    if let username = resolved.user.username {
                        LabeledContent("Username", value: "\(username).tribe")
                    }
                } header: {
                    Text("Found this TID on the hub")
                } footer: {
                    Text("The phrase recovers the wallet that registered this TID. To sign protocol envelopes, paste the app-key seed below — you can find it in tribe-app under Settings → View app key, or restore a full backup file from the previous screen instead.")
                }

                Section {
                    TextEditor(text: $appKeyInput)
                        .frame(minHeight: 64)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                } header: {
                    Text("App key (base64)")
                }

                Section {
                    Button {
                        Task { await adopt() }
                    } label: {
                        HStack {
                            if adopting { ProgressView() }
                            Text(adopting ? "Signing in…" : "Sign in")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(adopting || appKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Sign in with seed phrase")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func resolve() async {
        resolving = true
        defer { resolving = false }
        error = nil
        do {
            let (address, _) = try SolanaHD.keypair(fromMnemonic: phraseInput)
            guard let user = try await app.api.fetchTidByWallet(address) else {
                error = "No TID is registered to this wallet on \(app.hubBaseURL.host ?? "this hub"). Make sure you're pointing at the right hub, or finish onboarding in tribe-app first."
                return
            }
            resolved = ResolvedWallet(address: address, user: user)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func adopt() async {
        guard let resolved else { return }
        adopting = true
        defer { adopting = false }
        error = nil
        do {
            let appKey = try AppKey.restore(seedBase64: appKeyInput)
            try app.adopt(tid: resolved.user.tid, appKey: appKey)
            app.walletAddress = resolved.address
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func short(_ s: String) -> String {
        guard s.count > 10 else { return s }
        return "\(s.prefix(5))…\(s.suffix(5))"
    }
}
