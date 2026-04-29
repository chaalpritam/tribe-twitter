import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var hubInput: String = ""
    @State private var tidInput: String = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("Your TID", text: $tidInput)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Identity")
            } footer: {
                Text("Your TID is the on-chain identity created during onboarding in tribe-app. The iOS app uses it to fetch notifications, karma, and your activity. Onboarding (registering a fresh TID) is not implemented here yet — it needs the Solana program calls ported.")
            }

            Section {
                TextField("Hub base URL", text: $hubInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Hub")
            } footer: {
                Text("Defaults to http://127.0.0.1:4000. Override when running against a peer's hub or a deployed seed node.")
            }

            Section {
                Button {
                    save()
                } label: {
                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Save")
                    }
                }
            }

            Section("About") {
                LabeledContent("Cluster", value: Config.solanaCluster)
                LabeledContent("Hub", value: app.hubBaseURL.absoluteString)
                if let tid = app.myTID {
                    LabeledContent("TID", value: tid)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            hubInput = app.hubBaseURL.absoluteString
            tidInput = app.myTID ?? ""
        }
    }

    private func save() {
        let trimmed = hubInput.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            app.hubBaseURL = url
        }
        let tid = tidInput.trimmingCharacters(in: .whitespaces)
        app.myTID = tid.isEmpty ? nil : tid
        saved = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { saved = false }
        }
    }
}
