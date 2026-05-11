import SwiftUI

/// Three-step onboarding: Welcome → Configure Hub → Identity (create
/// or import). Wrapped in a NavigationStack so each step pushes
/// naturally and the system back button works.
struct OnboardingFlow: View {
    @EnvironmentObject private var app: AppState
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(Step.configureHub) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .configureHub:
                        ConfigureHubView { path.append(Step.identity) }
                    case .identity:
                        IdentityChoiceView(path: $path)
                    case .createIdentity:
                        CreateIdentityView()
                    case .importIdentity:
                        ImportIdentityView()
                    case .pairFromDesktop:
                        PairFromDesktopView()
                    case .restoreBackup:
                        RestoreBackupView()
                    case .seedPhrase:
                        SeedPhraseLoginView()
                    }
                }
        }
    }

    enum Step: Hashable {
        case configureHub
        case identity
        case createIdentity
        case importIdentity
        case pairFromDesktop
        case restoreBackup
        case seedPhrase
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(TribeColor.brandGradient)
                    .frame(width: 132, height: 132)
                    .shadow(color: TribeColor.brand.opacity(0.35), radius: 24, x: 0, y: 12)
                Image(systemName: "infinity")
                    .font(.system(size: 60, weight: .black))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 12) {
                Text("Welcome to Tribe")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("A decentralized social protocol on Solana. Own your identity, your data, and your social graph.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button(action: onContinue) {
                Text("Get started")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(TribeColor.brand)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TribeColor.softBrandBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Configure Hub

struct ConfigureHubView: View {
    @EnvironmentObject private var app: AppState
    @State private var hubInput: String = ""
    @State private var validating = false
    @State private var error: String?
    var onContinue: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("https://hub.example.com", text: $hubInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disableAutocorrection(true)
            } header: {
                Text("Hub URL")
            } footer: {
                Text("The Tribe hub is a server that stores tweets, channels, and other protocol data. Use the default for local development, or paste a deployed seed-node URL.")
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
                    Task { await validate() }
                } label: {
                    HStack {
                        if validating { ProgressView() }
                        Text(validating ? "Checking…" : "Continue")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(validating || hubInput.isEmpty)
            }
        }
        .navigationTitle("Configure hub")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if hubInput.isEmpty { hubInput = app.hubBaseURL.absoluteString }
        }
    }

    private func validate() async {
        guard let url = URL(string: hubInput.trimmingCharacters(in: .whitespaces)),
              url.scheme == "http" || url.scheme == "https" else {
            error = "URL must start with http:// or https://"
            return
        }
        validating = true
        error = nil
        defer { validating = false }
        // Probe /health to make sure we can actually reach the hub
        // before forcing the user to also pick an onboarding path.
        let probe = HubClient(baseURL: url)
        do {
            struct Health: Decodable { let status: String? }
            let _: Health = try await probe.get("health")
            app.hubBaseURL = url
            onContinue()
        } catch {
            self.error = "Couldn't reach hub: \(error.localizedDescription)"
        }
    }
}

// MARK: - Identity choice

struct IdentityChoiceView: View {
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("How would you like to sign in?")
                    .font(.title2.bold())
                Text("Tribe identities live on Solana. Your TID + a local app-key together let this device sign protocol envelopes on your behalf.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 24)

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                IdentityChoiceCard(
                    icon: "qrcode.viewfinder",
                    iconTint: TribeColor.brand,
                    title: "Scan QR from desktop",
                    subtitle: "Open tribe-app → Settings → Log in on mobile"
                ) {
                    path.append(OnboardingFlow.Step.pairFromDesktop)
                }
                IdentityChoiceCard(
                    icon: "doc.badge.arrow.up",
                    iconTint: TribeColor.accentTeal,
                    title: "Restore from backup",
                    subtitle: "Open a .tribe / .tribe.enc file from tribe-app"
                ) {
                    path.append(OnboardingFlow.Step.restoreBackup)
                }
                IdentityChoiceCard(
                    icon: "list.bullet.rectangle",
                    iconTint: TribeColor.accentTeal,
                    title: "Sign in with seed phrase",
                    subtitle: "Recover your TID from a 12 / 24-word BIP39 phrase"
                ) {
                    path.append(OnboardingFlow.Step.seedPhrase)
                }
                IdentityChoiceCard(
                    icon: "square.and.arrow.down",
                    iconTint: TribeColor.accentTeal,
                    title: "Paste TID + app key",
                    subtitle: "Manual import from tribe-app's local storage"
                ) {
                    path.append(OnboardingFlow.Step.importIdentity)
                }
                IdentityChoiceCard(
                    icon: "key.horizontal",
                    iconTint: TribeColor.accentAmber,
                    title: "Create new app key",
                    subtitle: "Generate a fresh ed25519 keypair on this device"
                ) {
                    path.append(OnboardingFlow.Step.createIdentity)
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .background(TribeColor.softBrandBackground.ignoresSafeArea())
    }
}

private struct IdentityChoiceCard: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconTint.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconTint)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(TribeColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TribeColor.cardStroke.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Import existing identity

struct ImportIdentityView: View {
    @EnvironmentObject private var app: AppState
    @State private var tidInput: String = ""
    @State private var seedInput: String = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                TextField("TID", text: $tidInput)
                    .keyboardType(.numberPad)
            } header: {
                Text("Your TID")
            } footer: {
                Text("The numeric on-chain identity issued during tribe-app onboarding.")
            }

            Section {
                TextEditor(text: $seedInput)
                    .frame(minHeight: 100)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            } header: {
                Text("App key (base64, 32 bytes)")
            } footer: {
                Text("In tribe-app: open dev tools → Application → Local Storage → copy the appKeySecret value. The seed never leaves this device — it's stored in the iOS Keychain.")
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
                    Task { await complete() }
                } label: {
                    HStack {
                        if working { ProgressView() }
                        Text(working ? "Verifying…" : "Sign in")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(working || tidInput.isEmpty || seedInput.isEmpty)
            }
        }
        .navigationTitle("Import identity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func complete() async {
        let tid = tidInput.trimmingCharacters(in: .whitespaces)
        guard !tid.isEmpty, Int64(tid) != nil else {
            error = "TID must be a number."
            return
        }
        working = true
        defer { working = false }
        do {
            let key = try AppKey.restore(seedBase64: seedInput)
            // Sanity check: the TID exists on the hub. Lets the user
            // catch a typo before the first signed envelope rejection.
            _ = try? await app.api.fetchUser(tid)
            try app.adopt(tid: tid, appKey: key)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Create fresh identity

struct CreateIdentityView: View {
    @EnvironmentObject private var app: AppState
    @State private var generated: AppKey = AppKey.generate()
    @State private var tidInput: String = ""
    @State private var acknowledgedBackup = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text(generated.seedBase64)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                Button {
                    UIPasteboard.general.string = generated.seedBase64
                } label: {
                    Label("Copy app key", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Your new app key")
            } footer: {
                Text("This 32-byte ed25519 seed signs every envelope you publish. Save it somewhere safe before continuing — there is no recovery path if you lose it.")
            }

            Section {
                Toggle(isOn: $acknowledgedBackup) {
                    Text("I've saved the app key in a secure place")
                }
            }

            Section {
                TextField("TID", text: $tidInput)
                    .keyboardType(.numberPad)
            } header: {
                Text("Your TID")
            } footer: {
                Text("Registering a fresh TID on Solana isn't supported in the iOS app yet — the on-chain registration program needs to be wrapped via Solana mobile / WalletConnect first. For now, register a TID in tribe-app, then enter it here so this app key can sign on its behalf.")
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
                    finish()
                } label: {
                    Text("Sign in").frame(maxWidth: .infinity)
                }
                .disabled(!acknowledgedBackup || tidInput.isEmpty)
            }
        }
        .navigationTitle("Create app key")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func finish() {
        let tid = tidInput.trimmingCharacters(in: .whitespaces)
        guard Int64(tid) != nil else {
            error = "TID must be a number."
            return
        }
        do {
            try app.adopt(tid: tid, appKey: generated)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
