import Foundation
import SwiftUI

/// Top-level app state. Carries:
///
///   - `phase`: drives the root view between Onboarding and the main
///              TabView. Computed from whether we have *both* a TID
///              and an app-key seed in the Keychain.
///   - `hubBaseURL`: the URL the HubClient hits. Persisted in
///                   UserDefaults so the user can rebuild from Settings
///                   without losing their identity.
///   - `myTID` + `myUsername` + `walletAddress`: the user's identity
///     surfaced to the rest of the UI.
///   - `appKey`: the ed25519 keypair used to sign protocol envelopes.
///     Loaded from the Keychain at launch and never written to disk
///     anywhere else.
///   - `api`: a HubClient configured to the current hubBaseURL.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        /// First launch (or after sign out): user needs to configure a
        /// hub URL and create or import an identity before we route
        /// them to the main TabView.
        case onboarding
        /// Identity is fully provisioned and the app shell can render.
        case ready
    }

    @Published var phase: Phase

    @Published var hubBaseURL: URL {
        didSet {
            UserDefaults.standard.set(hubBaseURL.absoluteString, forKey: Keys.hubURL)
            api = HubClient(baseURL: hubBaseURL)
        }
    }

    @Published var erBaseURL: URL {
        didSet {
            UserDefaults.standard.set(erBaseURL.absoluteString, forKey: Keys.erURL)
            er = ERClient(baseURL: erBaseURL)
        }
    }

    @Published var myTID: String? {
        didSet { persistTID(); recomputePhase() }
    }

    @Published private(set) var appKey: AppKey? {
        didSet { recomputePhase() }
    }

    /// x25519 keypair used for DM encryption. Lazy-loaded the first
    /// time something asks for it; nil until the user opens the DMs
    /// surface so the app launch doesn't generate a key just to throw
    /// it away on a user who never sends a DM.
    @Published private(set) var dmKey: DMKey?

    @Published var myUsername: String?
    @Published var walletAddress: String?

    private(set) var api: HubClient
    private(set) var er: ERClient
    /// Session-scoped like / bookmark sets. Lazy-loaded on first
    /// tweet-card render and kept in sync by the write paths.
    let interactions: InteractionCache

    init() {
        // One-time correctness gates: trap fast on startup if an
        // OS-level integer / endianness assumption ever breaks Blake3,
        // or if a refactor knocks the NaCl-box port off the
        // tweetnacl-compatible byte path.
        Blake3.selfTest()
        NaClBox.selfTest()

        let storedURL = UserDefaults.standard.string(forKey: Keys.hubURL)
            .flatMap(URL.init(string:)) ?? Config.defaultHubURL
        let storedERURL = UserDefaults.standard.string(forKey: Keys.erURL)
            .flatMap(URL.init(string:)) ?? Config.defaultERURL
        let storedTID = UserDefaults.standard.string(forKey: Keys.tid)

        // Restore the app key from Keychain if we have one.
        let restoredKey: AppKey?
        if let seed = try? KeychainStore.load(.appKeySeed),
           seed.count == 32,
           let restored = try? AppKey.restore(seedBase64: seed.base64EncodedString()) {
            restoredKey = restored
        } else {
            restoredKey = nil
        }

        self.hubBaseURL = storedURL
        self.erBaseURL = storedERURL
        self.myTID = storedTID
        self.api = HubClient(baseURL: storedURL)
        self.er = ERClient(baseURL: storedERURL)
        self.appKey = restoredKey
        self.phase = (storedTID != nil && restoredKey != nil) ? .ready : .onboarding

        // Cache is created empty and immediately attached. The cache
        // holds a weak ref back to self so it can read `api` and
        // `myTID` lazily without an init-order cycle.
        self.interactions = InteractionCache()
        self.interactions.attach(to: self)

        // Best-effort fetch of profile metadata so the UI shows the
        // right name / wallet on first paint after a relaunch.
        if let tid = storedTID {
            Task { [weak self] in await self?.refreshIdentityMetadata(tid: tid) }
        }
    }

    // MARK: - Onboarding handoff

    /// Persist a freshly created or imported identity. Called from
    /// the onboarding views once the user confirms their TID + app key.
    func adopt(tid: String, appKey: AppKey) throws {
        try KeychainStore.save(appKey.privateKey.rawRepresentation, for: .appKeySeed)
        self.appKey = appKey
        self.myTID = tid
        Task { [weak self] in
            await self?.refreshIdentityMetadata(tid: tid)
            await self?.interactions.refresh()
        }
    }

    /// Wipe the identity. Hub URL stays so the user doesn't have to
    /// re-enter it on a re-onboard. Routes back to onboarding.
    func signOut() {
        try? KeychainStore.delete(.appKeySeed)
        DMKey.clearKeychain()
        appKey = nil
        dmKey = nil
        myTID = nil
        myUsername = nil
        walletAddress = nil
        interactions.clear()
    }

    /// Lazy-load (or create + persist) the DM keypair. UI surfaces
    /// that need to encrypt or decrypt DMs call this; first call also
    /// publishes a DM_KEY_REGISTER envelope so peers can encrypt to
    /// us.
    @discardableResult
    func ensureDMKey() async throws -> DMKey {
        if let dm = dmKey { return dm }
        let key = try DMKey.loadOrCreate()
        await MainActor.run { self.dmKey = key }
        // Best-effort registration. If the hub is offline this will
        // surface to the caller; we don't trap because the app key
        // can still decrypt incoming DMs that arrive later.
        if let appKey, let myTID {
            _ = try? await api.registerDMKey(
                publicKey: key.publicKey,
                as: appKey,
                tid: myTID
            )
        }
        return key
    }

    func refreshIdentityMetadata() async {
        guard let tid = myTID else { return }
        await refreshIdentityMetadata(tid: tid)
    }

    private func refreshIdentityMetadata(tid: String) async {
        do {
            let user = try await api.fetchUser(tid)
            self.myUsername = user.username
            self.walletAddress = user.custodyAddress
        } catch {
            // Non-fatal: hub may be unreachable on first launch, profile
            // header just falls back to "TID #N".
        }
    }

    // MARK: - Internals

    private func persistTID() {
        if let tid = myTID {
            UserDefaults.standard.set(tid, forKey: Keys.tid)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.tid)
        }
    }

    private func recomputePhase() {
        phase = (myTID != nil && appKey != nil) ? .ready : .onboarding
    }

    private enum Keys {
        static let hubURL = "tribe.hubBaseURL"
        static let erURL = "tribe.erBaseURL"
        static let tid = "tribe.tid"
    }
}
