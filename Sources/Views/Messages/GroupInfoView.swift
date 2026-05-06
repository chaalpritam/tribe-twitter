import SwiftUI

/// Group info sheet pushed from DMThreadView's toolbar. Shows the
/// group name, full member list with usernames where available, and
/// a destructive "Leave group" action. The creator can't leave their
/// own group while there's no ownership transfer flow — the hub
/// rejects with 403, which we surface as an inline error.
///
/// On successful leave we fire `onLeft` so the parent thread view
/// can pop itself back to the inbox; the inbox refresh will drop
/// the group from the list naturally.
struct GroupInfoView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let group: DMGroup
    var onLeft: () -> Void

    @State private var details: DMGroupDetails?
    @State private var usernames: [String: String] = [:]
    @State private var loading = true
    @State private var leaving = false
    @State private var error: String?
    @State private var confirmLeave = false

    private var isCreator: Bool {
        guard let me = app.myTID, let d = details else { return false }
        return d.creatorTid == me
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Members") {
                    if loading && details == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let details {
                        ForEach(details.members) { member in
                            memberRow(member, isCreator: member.tid == details.creatorTid)
                        }
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if !isCreator {
                    Section {
                        Button(role: .destructive) {
                            confirmLeave = true
                        } label: {
                            HStack {
                                Spacer()
                                Text(leaving ? "Leaving…" : "Leave group")
                                Spacer()
                            }
                        }
                        .disabled(leaving)
                    } footer: {
                        Text("You'll stop receiving messages and won't appear in the member list. Re-joining requires the creator to add you back.")
                    }
                } else {
                    Section {} footer: {
                        Text("You created this group. Ownership transfer isn't supported yet — leaving will land in a follow-up.")
                    }
                }
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .confirmationDialog(
                "Leave \(group.name)?",
                isPresented: $confirmLeave,
                titleVisibility: .visible
            ) {
                Button("Leave", role: .destructive) {
                    Task { await leave() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func memberRow(_ member: DMGroupMember, isCreator: Bool) -> some View {
        let title = usernames[member.tid].map { "\($0).tribe" } ?? "TID #\(member.tid)"
        HStack(spacing: 12) {
            AvatarView(initial: String(title.prefix(1)).uppercased(), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text("Joined \(RelativeTime.short(member.joinedAt))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if isCreator {
                Text("Creator")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let d = try await app.api.fetchGroup(group.id)
            details = d
            // Resolve usernames in parallel; missing rows just stay TID-only.
            await withTaskGroup(of: (String, String?).self) { tg in
                for m in d.members {
                    tg.addTask {
                        let u = try? await self.app.api.fetchUser(m.tid)
                        return (m.tid, u?.username)
                    }
                }
                for await (tid, username) in tg {
                    if let username, !username.isEmpty {
                        usernames[tid] = username
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func leave() async {
        guard
            let key = app.appKey,
            let tid = app.myTID
        else { return }
        leaving = true
        error = nil
        defer { leaving = false }
        do {
            _ = try await app.api.leaveGroup(groupId: group.id, as: key, tid: tid)
            dismiss()
            onLeft()
        } catch {
            self.error = "Couldn't leave: \(error.localizedDescription)"
        }
    }
}
