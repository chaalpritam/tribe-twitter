import SwiftUI

/// Edit the user's profile metadata. Each field is its own
/// USER_DATA_ADD envelope (type 7); the hub keeps a per-tid history
/// and exposes the latest-per-field on /v1/user/:tid as `profile`.
///
/// Hub-enforced max value length is 500 characters; we mirror that
/// client-side so the user gets immediate feedback rather than a
/// post-publish rejection.
struct ProfileEditorView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var pfpURL: String = ""
    @State private var location: String = ""
    @State private var url: String = ""
    @State private var loading = true
    @State private var publishing = false
    @State private var error: String?
    @State private var savedFields: [String] = []

    private let maxLength = 500

    var body: some View {
        Form {
            Section {
                LabeledField(title: "Display name", text: $displayName, placeholder: "Anita")
                LabeledField(title: "Bio", text: $bio, placeholder: "Building tribe.", multiline: true)
                LabeledField(title: "Profile picture URL", text: $pfpURL, placeholder: "https://…")
                LabeledField(title: "Location", text: $location, placeholder: "Bangalore")
                LabeledField(title: "Link", text: $url, placeholder: "https://example.com")
            } header: {
                Text("Public profile")
            } footer: {
                Text("Each field is published as its own signed envelope. Empty fields are skipped — if you've never set a field, leaving it blank doesn't create a row.")
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if !savedFields.isEmpty {
                Section {
                    Label("Updated: \(savedFields.joined(separator: ", "))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await publish() }
                } label: {
                    HStack {
                        if publishing { ProgressView() }
                        Text(publishing ? "Publishing…" : "Publish changes")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(publishing || app.appKey == nil || app.myTID == nil)
            }
        }
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        defer { loading = false }
        guard let tid = app.myTID else { return }
        if let user = try? await app.api.fetchUser(tid) {
            displayName = user.profile?.displayName ?? ""
            bio = user.profile?.bio ?? ""
            pfpURL = user.profile?.pfpUrl ?? ""
        }
    }

    @MainActor
    private func publish() async {
        guard let key = app.appKey, let tid = app.myTID, !publishing else { return }
        publishing = true
        defer { publishing = false }
        error = nil
        savedFields = []

        let updates: [(String, String)] = [
            ("displayName", displayName.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("bio", bio.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("pfpUrl", pfpURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("location", location.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("url", url.trimmingCharacters(in: .whitespacesAndNewlines)),
        ].filter { !$0.1.isEmpty }

        for (field, value) in updates {
            if value.count > maxLength {
                error = "\(field) is over the 500-char limit."
                return
            }
            do {
                _ = try await app.api.updateProfile(field: field, value: value, as: key, tid: tid)
                savedFields.append(field)
            } catch {
                self.error = "\(field) failed: \(error.localizedDescription)"
                return
            }
        }
        await app.refreshIdentityMetadata()
    }
}

private struct LabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var multiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if multiline {
                TextEditor(text: $text)
                    .frame(minHeight: 80)
                    .font(.body)
            } else {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(title == "Display name" ? .words : .never)
                    .autocorrectionDisabled(title != "Display name" && title != "Bio")
            }
        }
        .padding(.vertical, 4)
    }
}
