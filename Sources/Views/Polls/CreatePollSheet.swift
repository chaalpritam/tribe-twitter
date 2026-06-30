import SwiftUI
import TribeCore

/// Compose sheet for a new poll. Hub validation:
///   - poll_id: `^[a-z0-9-]{1,64}$` (we slug from the question)
///   - 2–10 options
///   - expires_at: optional unix seconds
struct CreatePollSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onCreated: (() -> Void)? = nil

    @State private var question: String = ""
    @State private var options: [String] = ["", ""]
    @State private var expiresAt: Date = Date().addingTimeInterval(60 * 60 * 24)
    @State private var hasDeadline: Bool = false
    @State private var channelId: String = ""
    @State private var publishing = false
    @State private var error: String?

    private var validOptions: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canPublish: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validOptions.count >= 2 && validOptions.count <= 10
            && !publishing
            && app.appKey != nil
            && app.myTID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("What should we ship next?", text: $question, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ForEach(options.indices, id: \.self) { i in
                        HStack {
                            TextField("Option \(i + 1)", text: $options[i])
                            if options.count > 2 {
                                Button(role: .destructive) {
                                    options.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if options.count < 10 {
                        Button {
                            options.append("")
                        } label: {
                            Label("Add option", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Options (\(validOptions.count) of 2–10)")
                }

                Section {
                    Toggle("Set a deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Closes", selection: $expiresAt, in: Date()...)
                    }
                    TextField("Channel id (optional)", text: $channelId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Settings")
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
                            Text(publishing ? "Publishing…" : "Create poll")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canPublish)
                }
            }
            .navigationTitle("New poll")
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
        let id = Slug.make(question)
        do {
            _ = try await app.api.createPoll(
                pollId: id,
                question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                options: validOptions,
                expiresAt: hasDeadline ? expiresAt : nil,
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
