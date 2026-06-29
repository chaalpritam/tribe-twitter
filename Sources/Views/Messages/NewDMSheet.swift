import SwiftUI
import TribeCore

/// New conversation sheet. The user types a TID (or username search
/// result), we resolve their x25519 public key, encrypt the first
/// message, and POST DM_SEND. The hub provisions the conversation_id
/// from (tid_min, tid_max) so subsequent messages thread automatically.
struct NewDMSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onSent: (_ peerTID: String) -> Void

    @State private var peerInput: String = ""
    @State private var draft: String = ""
    @State private var sending = false
    @State private var error: String?

    private var canSend: Bool {
        !sending
            && Int64(peerInput.trimmingCharacters(in: .whitespaces)) != nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && app.appKey != nil
            && app.myTID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient TID") {
                    TextField("e.g. 1234", text: $peerInput)
                        .keyboardType(.numberPad)
                }

                Section("Message") {
                    TextEditor(text: $draft)
                        .frame(minHeight: 120)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if sending { ProgressView() }
                            Text(sending ? "Sending…" : "Send")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSend)
                }
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func send() async {
        guard
            let key = app.appKey,
            let tid = app.myTID
        else { return }
        sending = true
        error = nil
        defer { sending = false }
        let peer = peerInput.trimmingCharacters(in: .whitespaces)
        do {
            let dm = try await app.ensureDMKey()
            guard let peerPub = try await app.api.fetchDMPublicKey(peer) else {
                error = "TID #\(peer) hasn't registered a DM key yet."
                return
            }
            let nonce = NaClBox.randomNonce()
            let plaintext = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                .data(using: .utf8) ?? Data()
            let cipher = try NaClBox.box(
                plaintext,
                nonce: nonce,
                recipientPublicKey: peerPub,
                senderPrivateKey: dm.privateKey
            )
            _ = try await app.api.sendDM(
                recipientTID: peer,
                ciphertext: cipher,
                nonce: nonce,
                senderX25519: dm.publicKey,
                as: key,
                tid: tid
            )
            onSent(peer)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
