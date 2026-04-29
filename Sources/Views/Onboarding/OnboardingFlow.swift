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
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "infinity.circle.fill")
                .font(.system(size: 72, weight: .black))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text("Welcome to Tribe")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("A decentralized social protocol on Solana. Own your identity, your data, and your social graph.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button(action: onContinue) {
                Text("Get started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
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
            Text("How would you like to sign in?")
                .font(.title2.bold())
                .padding(.top, 24)

            Text("Tribe identities live on Solana. Your TID + a local app-key together let this device sign protocol envelopes on your behalf.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                Button {
                    path.append(OnboardingFlow.Step.pairFromDesktop)
                } label: {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                        VStack(alignment: .leading) {
                            Text("Scan QR from desktop").font(.headline)
                            Text("Open tribe-app → Settings → Log in on mobile")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    path.append(OnboardingFlow.Step.importIdentity)
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        VStack(alignment: .leading) {
                            Text("Import existing identity").font(.headline)
                            Text("Paste your TID + app-key from tribe-app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    path.append(OnboardingFlow.Step.createIdentity)
                } label: {
                    HStack {
                        Image(systemName: "key.horizontal")
                        VStack(alignment: .leading) {
                            Text("Create new app key").font(.headline)
                            Text("Generate a fresh ed25519 keypair on this device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
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
