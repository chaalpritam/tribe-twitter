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

    @Published var myTID: String? {
        didSet { persistTID(); recomputePhase() }
    }

    @Published private(set) var appKey: AppKey? {
        didSet { recomputePhase() }
    }

    @Published var myUsername: String?
    @Published var walletAddress: String?

    private(set) var api: HubClient

    init() {
        // One-time correctness gate: trap fast on startup if an
        // OS-level integer / endianness assumption ever breaks Blake3.
        Blake3.selfTest()

        let storedURL = UserDefaults.standard.string(forKey: Keys.hubURL)
            .flatMap(URL.init(string:)) ?? Config.defaultHubURL
        self.hubBaseURL = storedURL
        self.myTID = UserDefaults.standard.string(forKey: Keys.tid)
        self.api = HubClient(baseURL: storedURL)

        // Restore the app key from Keychain if we have one.
        if let seed = try? KeychainStore.load(.appKeySeed),
           seed.count == 32,
           let restored = try? AppKey.restore(seedBase64: seed.base64EncodedString()) {
            self.appKey = restored
        } else {
            self.appKey = nil
        }

        self.phase = (myTID != nil && self.appKey != nil) ? .ready : .onboarding

        // Best-effort fetch of profile metadata so the UI shows the
        // right name / wallet on first paint after a relaunch.
        if let tid = myTID {
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
        Task { [weak self] in await self?.refreshIdentityMetadata(tid: tid) }
    }

    /// Wipe the identity. Hub URL stays so the user doesn't have to
    /// re-enter it on a re-onboard. Routes back to onboarding.
    func signOut() {
        try? KeychainStore.delete(.appKeySeed)
        appKey = nil
        myTID = nil
        myUsername = nil
        walletAddress = nil
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
        static let tid = "tribe.tid"
    }
}
