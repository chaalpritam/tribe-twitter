import SwiftUI
import TribeCore

/// Build a `.tribe` (plain JSON) or `.tribe.enc` (AES-GCM, password-
/// derived) backup of this device's identity and hand the result off
/// to the system share sheet so the user can save it to Files,
/// iCloud, AirDrop, etc. Same wire format as tribe-app's exporter, so
/// the file round-trips between web and iOS.
struct ExportBackupSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var encrypt = true
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var preparedFile: PreparedFile?
    @State private var working = false

    private var passwordsMatch: Bool { password == confirm && !password.isEmpty }
    private var canExport: Bool {
        guard app.appKey != nil, app.myTID != nil else { return false }
        if encrypt { return passwordsMatch }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Encrypt with password", isOn: $encrypt)
                } footer: {
                    Text(encrypt
                        ? "AES-256-GCM with a key derived via PBKDF2(SHA-256, 100k iters). Same format as tribe-app's encrypted backups."
                        : "Cleartext JSON. Anyone who opens the file can read the app-key seed.")
                }

                if encrypt {
                    Section {
                        SecureField("Password", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Confirm password", text: $confirm)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !password.isEmpty && !confirm.isEmpty && password != confirm {
                            Label("Passwords don't match", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                        }
                    } header: {
                        Text("Password")
                    } footer: {
                        Text("There's no recovery if you lose this password — the file becomes unopenable.")
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await prepare() }
                    } label: {
                        HStack {
                            if working { ProgressView() }
                            Text(working ? "Preparing…" : "Prepare backup")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canExport || working)

                    if let preparedFile {
                        ShareLink(item: preparedFile.url) {
                            Label("Share \(preparedFile.url.lastPathComponent)",
                                  systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Export account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func prepare() async {
        guard let tid = app.myTID, let appKey = app.appKey else { return }
        working = true
        defer { working = false }
        error = nil
        // Load the DM key if one already lives in the Keychain.
        // We don't *create* a fresh one here; the absence of a DM
        // key just leaves the field null in the payload (a user who
        // has never opened DMs has nothing to back up).
        let dm = try? DMKey.loadIfExists()

        let backup = BackupFile.build(
            tid: tid,
            walletAddress: app.walletAddress,
            appKey: appKey,
            dmKey: dm,
            browserWalletJSON: BackupFile.storedBrowserWalletJSON()
        )

        do {
            let url: URL
            if encrypt {
                let encrypted = try backup.encrypted(password: password)
                url = try writeTemp(text: encrypted, ext: "tribe.enc", tid: tid)
            } else {
                let plain = try backup.encoded()
                url = try writeTemp(data: plain, ext: "tribe", tid: tid)
            }
            preparedFile = PreparedFile(url: url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func writeTemp(text: String, ext: String, tid: String) throws -> URL {
        try writeTemp(data: Data(text.utf8), ext: ext, tid: tid)
    }

    private func writeTemp(data: Data, ext: String, tid: String) throws -> URL {
        let stamp = isoStamp()
        let filename = "tribe-\(tid)-\(stamp).\(ext)"
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func isoStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

private struct PreparedFile: Equatable {
    let url: URL
}
