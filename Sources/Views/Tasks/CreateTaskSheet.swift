import SwiftUI

/// Compose sheet for a new task (TASK_ADD type 20). The protocol
/// doesn't escrow funds — `reward_text` is a free-form description of
/// the reward, and the on-chain task-registry is a separate flow.
struct CreateTaskSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onCreated: (() -> Void)? = nil

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var rewardText: String = ""
    @State private var channelId: String = ""
    @State private var publishing = false
    @State private var error: String?

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !publishing
            && app.appKey != nil
            && app.myTID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Document the gossip protocol", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    TextField("e.g. 50 USDC, T-shirt, …", text: $rewardText)
                } header: {
                    Text("Reward (free-form)")
                } footer: {
                    Text("The protocol doesn't escrow rewards — this is descriptive text that the claimer can read before deciding to take the task on.")
                }

                Section {
                    TextField("Channel id (optional)", text: $channelId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Optional")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await publish() }
                    } label: {
                        HStack {
                            if publishing { ProgressView() }
                            Text(publishing ? "Publishing…" : "Create task")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canPublish)
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func publish() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        publishing = true
        defer { publishing = false }
        let id = Slug.make(title)
        do {
            _ = try await app.api.createTask(
                taskId: id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                rewardText: rewardText.trimmingCharacters(in: .whitespacesAndNewlines),
                channelId: channelId.trimmingCharacters(in: .whitespacesAndNewlines),
                as: key,
                tid: tid
            )
            onCreated?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
