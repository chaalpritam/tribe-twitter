import SwiftUI

/// Inbox combining 1:1 DM conversations and groups the user belongs
/// to. Tapping a row pushes the shared thread view (DMThreadView,
/// switched on a DMTarget enum). The toolbar carries a New Message
/// button for 1:1; group creation lands in a follow-up.
///
/// Both lists are pulled from the hub; ordering by last_message_at /
/// created_at already happens server-side.
struct MessagesView: View {
    @EnvironmentObject private var app: AppState
    @State private var conversations: [DMConversation] = []
    @State private var groups: [DMGroup] = []
    @State private var loading = true
    @State private var error: String?
    @State private var presentingNew = false

    private var isEmpty: Bool { conversations.isEmpty && groups.isEmpty }

    var body: some View {
        Group {
            if loading && isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load messages",
                    message: error,
                    action: ("Retry", { Task { await refresh() } })
                )
            } else if isEmpty {
                EmptyStateView(
                    symbol: "envelope",
                    title: "No conversations yet",
                    message: "DMs are end-to-end encrypted with nacl.box. Tap + to start a new one."
                )
            } else {
                List {
                    if !groups.isEmpty {
                        SwiftUI.Section("Groups") {
                            ForEach(groups) { g in
                                NavigationLink {
                                    DMThreadView(target: .group(g))
                                } label: {
                                    GroupRow(group: g)
                                }
                            }
                        }
                    }
                    if !conversations.isEmpty {
                        SwiftUI.Section(groups.isEmpty ? "" : "Direct Messages") {
                            ForEach(conversations) { c in
                                NavigationLink {
                                    DMThreadView(target: .oneOnOne(c))
                                } label: {
                                    ConversationRow(conversation: c)
                                }
                            }
                        }
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
        loading = isEmpty
        defer { loading = false }
        error = nil
        async let convs = app.api.fetchConversations(tid)
        async let grps = app.api.fetchGroups(tid)
        do {
            conversations = try await convs
        } catch {
            self.error = error.localizedDescription
        }
        // Groups are best-effort — failure here shouldn't kill the inbox.
        groups = (try? await grps) ?? []
    }
}

private struct GroupRow: View {
    let group: DMGroup

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initial: initial, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.headline)
                Text("\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "person.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var initial: String {
        if let first = group.name.first { return String(first).uppercased() }
        return "#"
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
            VStack(alignment: .trailing, spacing: 4) {
                if let last = conversation.lastMessageAt {
                    Text(RelativeTime.short(last))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }
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
