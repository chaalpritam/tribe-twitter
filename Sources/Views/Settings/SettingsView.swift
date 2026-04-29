import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var hubInput: String = ""
    @State private var saved = false
    @State private var showingSignOut = false
    @State private var showingAppKey = false

    var body: some View {
        Form {
            Section {
                if let tid = app.myTID {
                    LabeledContent("TID", value: tid)
                    if let username = app.myUsername {
                        LabeledContent("Username", value: "\(username).tribe")
                    }
                    if let address = app.walletAddress {
                        LabeledContent("Wallet") {
                            Text(short(address))
                                .font(.system(.footnote, design: .monospaced))
                        }
                    }
                    Button("View app key") { showingAppKey = true }
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Identity")
            } footer: {
                Text("Your app key signs every protocol envelope you publish from this device. Keep the seed somewhere safe — losing it means re-registering on tribe-app.")
            }

            Section {
                TextField("Hub base URL", text: $hubInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    saveHub()
                } label: {
                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Save")
                    }
                }
            } header: {
                Text("Hub")
            } footer: {
                Text("Switching hubs reroutes all reads and writes immediately. Defaults to http://127.0.0.1:4000.")
            }

            Section("About") {
                LabeledContent("Cluster", value: Config.solanaCluster)
                LabeledContent("Hub", value: app.hubBaseURL.absoluteString)
            }

            if app.myTID != nil {
                Section {
                    Button(role: .destructive) {
                        showingSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            hubInput = app.hubBaseURL.absoluteString
        }
        .confirmationDialog(
            "Sign out of this device?",
            isPresented: $showingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) { app.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your app key will be deleted from this device's Keychain. The TID stays registered on Solana — re-import on this device with the same seed to come back online.")
        }
        .sheet(isPresented: $showingAppKey) {
            AppKeySheet()
                .environmentObject(app)
        }
    }

    private func saveHub() {
        let trimmed = hubInput.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            app.hubBaseURL = url
            saved = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { saved = false }
            }
        }
    }

    private func short(_ s: String) -> String {
        guard s.count > 10 else { return s }
        return "\(s.prefix(5))…\(s.suffix(5))"
    }
}

private struct AppKeySheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if revealed {
                        if let key = app.appKey {
                            Text(key.seedBase64)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                            Button {
                                UIPasteboard.general.string = key.seedBase64
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        } else {
                            Text("No app key loaded.").foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            revealed = true
                        } label: {
                            Label("Reveal app key", systemImage: "eye")
                        }
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Anyone with this seed can post envelopes on your behalf and read messages encrypted to your DM key. Keep it as private as your wallet seed.")
                }
            }
            .navigationTitle("App key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
