import Foundation
import CryptoKit

/// The 32-byte ed25519 app key used to sign every protocol envelope.
/// CryptoKit's `Curve25519.Signing.PrivateKey` is the raw 32-byte seed;
/// the public key is derived deterministically.
struct AppKey {
    let privateKey: Curve25519.Signing.PrivateKey
    var publicKey: Curve25519.Signing.PublicKey { privateKey.publicKey }

    /// 32-byte raw seed, base64-encoded. This is what the user backs
    /// up and what the iOS app stores in the Keychain.
    var seedBase64: String { privateKey.rawRepresentation.base64EncodedString() }

    /// Public key encoded the way every other tribe-eco component
    /// expects it: 32 bytes, base64.
    var publicKeyBase64: String { publicKey.rawRepresentation.base64EncodedString() }

    /// Generate a fresh keypair locally. The seed needs to be backed
    /// up before the user closes the onboarding sheet — there's no
    /// recovery path other than the original 32-byte seed.
    static func generate() -> AppKey {
        AppKey(privateKey: Curve25519.Signing.PrivateKey())
    }

    /// Restore an app key from a base64-encoded ed25519 secret.
    /// Accepts both the 32-byte seed form (what iOS stores in the
    /// Keychain) and the 64-byte nacl `secretKey` form (seed || pubkey,
    /// what tribe-app's backup payloads use) — the first 32 bytes are
    /// the seed in both cases.
    static func restore(seedBase64: String) throws -> AppKey {
        let trimmed = seedBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: trimmed) else {
            throw AppKeyError.notBase64
        }
        let seed: Data
        switch raw.count {
        case 32: seed = raw
        case 64: seed = Data(raw.prefix(32))
        default: throw AppKeyError.wrongLength(raw.count)
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        return AppKey(privateKey: key)
    }

    /// Sign 32-byte content (typically the blake3 hash of canonical
    /// envelope bytes). Returns the 64-byte ed25519 signature.
    func sign(_ digest: Data) throws -> Data {
        try privateKey.signature(for: digest)
    }
}

enum AppKeyError: LocalizedError {
    case notBase64
    case wrongLength(Int)

    var errorDescription: String? {
        switch self {
        case .notBase64:
            return "App key must be valid base64."
        case .wrongLength(let n):
            return "App key must be 32 or 64 bytes; got \(n)."
        }
    }
}
