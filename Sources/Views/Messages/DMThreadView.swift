import SwiftUI

/// Thread of a 1:1 conversation or a group. Decrypts ciphertext rows
/// client-side using nacl.box.open with the sender's x25519 pubkey
/// (stored on each row) and the local DM keypair.
///
/// For 1:1 the composer is pinned at the bottom; on send it encrypts
/// the new message, posts the DM_SEND envelope, and appends the
/// rendered plaintext locally so the user sees their own message
/// immediately without a round-trip.
///
/// Groups currently render read-only — Phase 1 of group DM support
/// ships the inbox + decrypted thread; per-recipient encryption for
/// outgoing group messages lands in a follow-up.
struct DMThreadView: View {
    @EnvironmentObject private var app: AppState
    let target: DMTarget

    @State private var messages: [DMMessage] = []
    @State private var rendered: [String: String] = [:]   // hash → plaintext (or null marker)
    @State private var draft: String = ""
    @State private var loading = true
    @State private var sending = false
    @State private var error: String?
    @State private var recipientPub: Data?

    private var isGroup: Bool {
        if case .group = target { return true }
        return false
    }

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

            if isGroup {
                Text("Group sending coming soon")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
            } else {
                composer
            }
        }
        .navigationTitle(target.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
            // Only 1:1 needs the peer's pubkey for own-message decryption.
            if case .oneOnOne(let conv) = target {
                recipientPub = try? await app.api.fetchDMPublicKey(conv.peerTid)
            }
        }
        .refreshable { await refresh() }
    }

    private var composer: some View {
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
            switch target {
            case .oneOnOne(let conv):
                messages = try await app.api.fetchDMMessages(
                    conversationId: conv.id,
                    tid: tid
                )
                await decryptMissing()
                await markRead(tid: tid, conversationId: conv.id)
            case .group(let group):
                messages = try await app.api.fetchGroupMessages(
                    groupId: group.id,
                    tid: tid
                )
                await decryptMissing()
                // No group read-receipts endpoint yet — skip.
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func markRead(tid: String, conversationId: String) async {
        // Best-effort: post a DM_READ envelope for the latest message
        // we've rendered so the hub can compute unread counts. Failures
        // here are silent — the receipt is purely cosmetic.
        guard
            let key = app.appKey,
            let last = messages.last
        else { return }
        _ = try? await app.api.markDMRead(
            conversationId: conversationId,
            lastReadHash: last.hash,
            as: key,
            tid: tid
        )
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
            let isOwn = msg.senderTid == app.myTID
            // For 1:1 own messages we used the peer's pubkey at send
            // time, so we need to swap identities to decrypt the echo.
            // For group own messages the hub returns the row keyed on
            // ourselves as recipient — the ciphertext was already
            // encrypted under our own pubkey, so the standard
            // sender-key path works without recipientPub.
            if isOwn, case .oneOnOne = target {
                guard let peerPub = recipientPub else {
                    rendered[msg.hash] = "[no peer key]"
                    continue
                }
                if let pt = try? NaClBox.boxOpen(
                    cipher,
                    nonce: nonce,
                    senderPublicKey: peerPub,
                    recipientPrivateKey: dm.privateKey
                ) {
                    rendered[msg.hash] = String(data: pt, encoding: .utf8) ?? "[non-utf8]"
                } else {
                    rendered[msg.hash] = "[unable to decrypt]"
                }
                continue
            }
            let senderPubB64 = msg.senderX25519
                ?? (isOwn ? dm.publicKey.base64EncodedString() : nil)
            guard
                let pubB64 = senderPubB64,
                let senderPub = Data(base64Encoded: pubB64)
            else {
                rendered[msg.hash] = "[no sender key]"
                continue
            }
            if let pt = try? NaClBox.boxOpen(
                cipher,
                nonce: nonce,
                senderPublicKey: senderPub,
                recipientPrivateKey: dm.privateKey
            ) {
                rendered[msg.hash] = String(data: pt, encoding: .utf8) ?? "[non-utf8]"
            } else {
                rendered[msg.hash] = "[unable to decrypt]"
            }
        }
    }

    @MainActor
    private func send() async {
        guard case .oneOnOne(let conv) = target else { return }
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
                recipientTID: conv.peerTid,
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
