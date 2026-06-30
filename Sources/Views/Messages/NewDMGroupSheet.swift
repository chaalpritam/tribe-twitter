import SwiftUI
import TribeCore

/// New group sheet. The user picks a name and types peer TIDs
/// (comma- or newline-separated). On submit we generate a random
/// group_id, prepend our own TID to the member list so we can post
/// + read in the new group, and POST a DM_GROUP_CREATE envelope.
///
/// First message goes through the regular composer in DMThreadView
/// after creation — keeping this sheet focused on group setup.
struct NewDMGroupSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onCreated: (_ groupId: String) -> Void

    @State private var name: String = ""
    @State private var membersInput: String = ""
    @State private var creating = false
    @State private var error: String?

    private var parsedMemberTIDs: [String] {
        membersInput
            .split(whereSeparator: { $0 == "," || $0.isNewline || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && Int64($0) != nil }
    }

    private var canCreate: Bool {
        !creating
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !parsedMemberTIDs.isEmpty
            && app.appKey != nil
            && app.myTID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Trip planning", text: $name)
                }

                Section {
                    TextEditor(text: $membersInput)
                        .frame(minHeight: 100)
                        .keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("Member TIDs")
                } footer: {
                    Text("Comma- or newline-separated. Your own TID is added automatically. Members without a registered DM key won't be able to read messages until they register.")
                }

                if !parsedMemberTIDs.isEmpty {
                    Section("Will invite") {
                        ForEach(parsedMemberTIDs, id: \.self) { tid in
                            Text("TID #\(tid)")
                                .font(.subheadline.monospaced())
                        }
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            if creating { ProgressView() }
                            Text(creating ? "Creating…" : "Create group")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canCreate)
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func create() async {
        guard
            let key = app.appKey,
            let myTID = app.myTID
        else { return }
        creating = true
        error = nil
        defer { creating = false }

        // Generate a group_id matching /^[a-z0-9-]{1,64}$/. UUIDs are
        // 36 chars of [0-9a-f-] when lowercased — well under the limit.
        let groupId = "g-" + UUID().uuidString.lowercased()
        // De-dupe in case the user typed their own TID by mistake.
        let memberTIDs = Array(Set([myTID] + parsedMemberTIDs))
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        do {
            _ = try await app.api.createGroup(
                groupId: groupId,
                name: trimmedName,
                memberTIDs: memberTIDs,
                as: key,
                tid: myTID
            )
            onCreated(groupId)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
