import Foundation
import CryptoKit

/// Persistent x25519 keypair used for nacl.box DM encryption.
///
/// Unlike tribe-app (which stores its DM keypair in sessionStorage and
/// loses it on tab close), iOS keeps the seed in the Keychain so the
/// user can read past DMs after a relaunch / re-onboard with the same
/// app key.
///
/// The DM key is *separate* from the app (signing) key — x25519 is
/// distinct from ed25519, even though both are Curve25519 curves —
/// because the protocol publishes the x25519 public via DM_KEY_REGISTER
/// envelopes so other clients can encrypt to us.
struct DMKey {
    let privateKey: Data    // 32-byte raw seed
    let publicKey: Data     // 32-byte x25519 public

    var publicKeyBase64: String { publicKey.base64EncodedString() }

    static func generate() -> DMKey {
        let pair = NaClBox.generateKeyPair()
        return DMKey(privateKey: pair.privateKey, publicKey: pair.publicKey)
    }

    static func restore(seed: Data) throws -> DMKey {
        guard seed.count == 32 else { throw NaClBox.Error.invalidKeyLength }
        let sk = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: seed)
        return DMKey(privateKey: Data(sk.rawRepresentation), publicKey: Data(sk.publicKey.rawRepresentation))
    }

    /// Load the stored DM key, or generate + persist a new one if
    /// none exists. The seed lives under the same Keychain access
    /// flag as the app key.
    static func loadOrCreate() throws -> DMKey {
        if let raw = try? KeychainStore.load(.dmKeySeed),
           raw.count == 32,
           let restored = try? restore(seed: raw) {
            return restored
        }
        let fresh = generate()
        try KeychainStore.save(fresh.privateKey, for: .dmKeySeed)
        return fresh
    }

    static func clearKeychain() {
        try? KeychainStore.delete(.dmKeySeed)
    }
}
