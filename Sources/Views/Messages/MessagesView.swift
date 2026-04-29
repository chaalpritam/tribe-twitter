import SwiftUI

/// Inbox of 1:1 DM conversations. Tapping a row pushes the thread
/// view; the toolbar carries a New Message button.
///
/// Conversations are pulled from the hub; ordering by last_message_at
/// already happens server-side. The list shows the peer's username
/// (when known) and the count of messages so the user can spot
/// unread chatter at a glance.
struct MessagesView: View {
    @EnvironmentObject private var app: AppState
    @State private var conversations: [DMConversation] = []
    @State private var loading = true
    @State private var error: String?
    @State private var presentingNew = false

    var body: some View {
        Group {
            if loading && conversations.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, conversations.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load messages",
                    message: error,
                    action: ("Retry", { Task { await refresh() } })
                )
            } else if conversations.isEmpty {
                EmptyStateView(
                    symbol: "envelope",
                    title: "No conversations yet",
                    message: "DMs are end-to-end encrypted with nacl.box. Tap + to start a new one."
                )
            } else {
                List(conversations) { c in
                    NavigationLink {
                        DMThreadView(conversation: c)
                    } label: {
                        ConversationRow(conversation: c)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentingNew = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New message")
            }
        }
        .task {
            try? await app.ensureDMKey()
            await refresh()
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $presentingNew) {
            NewDMSheet { tid in
                Task {
                    presentingNew = false
                    await refresh()
                    // Best-effort jump into the newly-created thread:
                    // the conversation_id only materializes once the
                    // first message lands, so we just refresh for now.
                    _ = tid
                }
            }
            .environmentObject(app)
            .presentationDetents([.medium])
        }
    }

    @MainActor
    private func refresh() async {
        guard let tid = app.myTID else {
            loading = false
            return
        }
        loading = conversations.isEmpty
        defer { loading = false }
        error = nil
        do {
            conversations = try await app.api.fetchConversations(tid)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ConversationRow: View {
    let conversation: DMConversation

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initial: initial, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                Text("\(conversation.messageCount) message\(conversation.messageCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let last = conversation.lastMessageAt {
                Text(RelativeTime.short(last))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        if let u = conversation.peerUsername, !u.isEmpty { return "\(u).tribe" }
        return "TID #\(conversation.peerTid)"
    }

    private var initial: String {
        if let u = conversation.peerUsername, let first = u.first { return String(first).uppercased() }
        return String(conversation.peerTid.prefix(1))
    }
}
