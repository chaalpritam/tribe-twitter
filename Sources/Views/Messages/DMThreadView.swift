import SwiftUI

/// Thread of an individual conversation. Decrypts ciphertext rows
/// client-side using nacl.box.open with the sender's x25519 pubkey
/// (stored on each row) and the local DM keypair.
///
/// Composer is pinned at the bottom; on send it encrypts the new
/// message, posts the DM_SEND envelope, and appends the rendered
/// plaintext locally so the user sees their own message immediately
/// without a round-trip.
struct DMThreadView: View {
    @EnvironmentObject private var app: AppState
    let conversation: DMConversation

    @State private var messages: [DMMessage] = []
    @State private var rendered: [String: String] = [:]   // hash → plaintext (or null marker)
    @State private var draft: String = ""
    @State private var loading = true
    @State private var sending = false
    @State private var error: String?
    @State private var recipientPub: Data?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            MessageBubble(
                                message: msg,
                                plaintext: rendered[msg.hash] ?? "—",
                                isOwn: msg.senderTid == app.myTID
                            )
                            .id(msg.hash)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.hash, anchor: .bottom) }
                    }
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color(.tertiarySystemFill))
                    )
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: sending ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .padding(.top, 8)
            .background(
                Color(.systemBackground)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .navigationTitle(displayPeer)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
            recipientPub = try? await app.api.fetchDMPublicKey(conversation.peerTid)
        }
        .refreshable { await refresh() }
    }

    private var displayPeer: String {
        if let u = conversation.peerUsername, !u.isEmpty { return "\(u).tribe" }
        return "TID #\(conversation.peerTid)"
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sending
            && app.appKey != nil
            && app.myTID != nil
            && recipientPub != nil
            && app.dmKey != nil
    }

    @MainActor
    private func refresh() async {
        guard let tid = app.myTID else { loading = false; return }
        loading = messages.isEmpty
        defer { loading = false }
        do {
            messages = try await app.api.fetchDMMessages(
                conversationId: conversation.id,
                tid: tid
            )
            await decryptMissing()
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func decryptMissing() async {
        guard let dm = app.dmKey else {
            // Make sure the keypair is loaded before we attempt to
            // decrypt anything so the first thread visit succeeds.
            _ = try? await app.ensureDMKey()
            return
        }
        for msg in messages where rendered[msg.hash] == nil {
            guard
                let cipher = Data(base64Encoded: msg.ciphertext),
                let nonce = Data(base64Encoded: msg.nonce)
            else {
                rendered[msg.hash] = "[malformed ciphertext]"
                continue
            }
            // For incoming messages, sender_x25519 is on the row.
            // For our own messages echoed back from the hub, the row
            // also carries our pubkey, but we can fall back to it
            // explicitly if missing.
            let senderPubB64 = msg.senderX25519
                ?? (msg.senderTid == app.myTID ? dm.publicKey.base64EncodedString() : nil)
            guard
                let pubB64 = senderPubB64,
                let senderPub = Data(base64Encoded: pubB64)
            else {
                rendered[msg.hash] = "[no sender key]"
                continue
            }
            let recipientPriv: Data
            // Messages we sent ourselves were encrypted under the
            // peer's pubkey, but to decrypt them we need to swap
            // sender / recipient identities — nacl.box is symmetric
            // in that sense (DH shared secret is the same).
            if msg.senderTid == app.myTID {
                // We were the sender; the box was opened by the peer.
                // Replaying our own DMs requires box.open with peer
                // pub + our priv. We don't have peer pub here on the
                // row, but the hub returns the peer's pubkey on a
                // separate fetch — we already have it as recipientPub.
                guard let peerPub = recipientPub else {
                    rendered[msg.hash] = "[no peer key]"
                    continue
                }
                recipientPriv = dm.privateKey
                if let pt = try? NaClBox.boxOpen(
                    cipher,
                    nonce: nonce,
                    senderPublicKey: peerPub,
                    recipientPrivateKey: recipientPriv
                ) {
                    rendered[msg.hash] = String(data: pt, encoding: .utf8) ?? "[non-utf8]"
                } else {
                    rendered[msg.hash] = "[unable to decrypt]"
                }
                continue
            }
            recipientPriv = dm.privateKey
            if let pt = try? NaClBox.boxOpen(
                cipher,
                nonce: nonce,
                senderPublicKey: senderPub,
                recipientPrivateKey: recipientPriv
            ) {
                rendered[msg.hash] = String(data: pt, encoding: .utf8) ?? "[non-utf8]"
            } else {
                rendered[msg.hash] = "[unable to decrypt]"
            }
        }
    }

    @MainActor
    private func send() async {
        guard
            let key = app.appKey,
            let tid = app.myTID,
            let dm = app.dmKey,
            let peerPub = recipientPub,
            !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        sending = true
        error = nil
        defer { sending = false }
        do {
            let plaintext = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                .data(using: .utf8) ?? Data()
            let nonce = NaClBox.randomNonce()
            let cipher = try NaClBox.box(
                plaintext,
                nonce: nonce,
                recipientPublicKey: peerPub,
                senderPrivateKey: dm.privateKey
            )
            _ = try await app.api.sendDM(
                recipientTID: conversation.peerTid,
                ciphertext: cipher,
                nonce: nonce,
                senderX25519: dm.publicKey,
                as: key,
                tid: tid
            )
            draft = ""
            await refresh()
        } catch {
            self.error = "Send failed: \(error.localizedDescription)"
        }
    }
}

private struct MessageBubble: View {
    let message: DMMessage
    let plaintext: String
    let isOwn: Bool

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(plaintext)
                    .font(.body)
                    .foregroundStyle(isOwn ? Color.white : Color.primary)
                Text(RelativeTime.short(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(isOwn ? Color.white.opacity(0.8) : Color(.tertiaryLabel))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOwn ? Color.accentColor : Color(.tertiarySystemFill))
            )
            if !isOwn { Spacer(minLength: 40) }
        }
    }
}
