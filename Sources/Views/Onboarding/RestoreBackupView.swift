import SwiftUI
import UniformTypeIdentifiers
import TribeCore

/// Onboarding step that restores an identity from a tribe-twitter-app
/// `.tribe` / `.tribe.enc` backup. Same JSON / encryption format as
/// `tribe-twitter-app/src/lib/backup.ts`, so files round-trip between web and
/// iOS.
struct RestoreBackupView: View {
    @EnvironmentObject private var app: AppState

    @State private var pickerShown = false
    @State private var pickedFileName: String?
    @State private var fileText: String?
    @State private var encrypted = false
    @State private var password = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                Button {
                    pickerShown = true
                } label: {
                    Label(
                        pickedFileName ?? "Choose backup file",
                        systemImage: "doc.badge.arrow.up"
                    )
                }
            } header: {
                Text("Backup file")
            } footer: {
                Text("Pick the `.tribe` or `.tribe.enc` file you exported from tribe-twitter-app (Settings → Export account) or from this app.")
            }

            if let pickedFileName, fileText != nil {
                if encrypted {
                    Section {
                        SecureField("Password", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Password")
                    } footer: {
                        Text("This file is encrypted. Enter the password you set when it was exported.")
                    }
                } else {
                    Section {
                        Label("Plain (unencrypted) backup", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    } footer: {
                        Text("\(pickedFileName) holds the app-key seed in cleartext. Only proceed if you trust the source.")
                    }
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if fileText != nil {
                Section {
                    Button {
                        Task { await restore() }
                    } label: {
                        HStack {
                            if working { ProgressView() }
                            Text(working ? "Restoring…" : "Restore account")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(working || (encrypted && password.isEmpty))
                }
            }
        }
        .navigationTitle("Restore from backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $pickerShown,
            // tribe-twitter-app writes both .tribe (JSON) and .tribe.enc
            // (base64). Neither has a registered UTType, so accept
            // anything and validate after read.
            allowedContentTypes: [.data]
        ) { result in
            handlePick(result)
        }
    }

    private func handlePick(_ result: Result<URL, Error>) {
        error = nil
        do {
            let url = try result.get()
            // .fileImporter hands back a security-scoped URL; the
            // grant only lasts inside the start/stop pair, so read
            // the contents immediately rather than holding the URL.
            guard url.startAccessingSecurityScopedResource() else {
                error = "Couldn't open that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                error = "File isn't UTF-8 text."
                return
            }
            pickedFileName = url.lastPathComponent
            fileText = text
            encrypted = BackupFile.isEncrypted(text)
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func restore() async {
        guard let fileText else { return }
        working = true
        defer { working = false }
        do {
            let backup = try BackupFile.decode(
                text: fileText,
                password: encrypted ? password : nil
            )
            let applied = try backup.apply()
            try app.adopt(tid: applied.tid, appKey: applied.appKey)
            if let wallet = applied.walletAddress {
                app.walletAddress = wallet
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
