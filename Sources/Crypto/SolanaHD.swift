import Foundation
import CryptoKit

/// SLIP-0010 ed25519 HD derivation for Solana wallets, plus Base58
/// address encoding. Matches what Phantom, Solflare, solana-keygen,
/// and the `ed25519-hd-key` npm package (which tribe-app uses)
/// produce from the same BIP39 seed at the same derivation path.
enum SolanaHD {
    /// Standard Solana derivation path. Account #0 is the first
    /// keypair derived from a phrase; account index varies the third
    /// segment so a user can pick which account to import.
    static func solanaPath(account: UInt32) -> String {
        "m/44'/501'/\(account)'/0'"
    }

    struct DerivedKey {
        /// 32-byte ed25519 seed. Plug into Curve25519.Signing or
        /// straight into the iOS Keychain as the app-key seed.
        let privateKey: Data
        /// 32-byte chain code; preserved across the derivation chain
        /// but the leaf-level wallet doesn't strictly need it.
        let chainCode: Data
    }

    /// Walk `path` from the master seed, returning the leaf private
    /// key + chain code. Only hardened segments are valid for ed25519
    /// (the spec doesn't define non-hardened derivation), so each
    /// segment must end with `'`.
    static func derive(seed: Data, path: String) throws -> DerivedKey {
        var current = masterKey(from: seed)
        for segment in try parsePath(path) {
            current = childKey(parent: current, index: segment)
        }
        return current
    }

    /// 32-byte ed25519 public key for a derived 32-byte seed. Same
    /// bytes Solana's Keypair.fromSeed produces.
    static func publicKey(privateKey: Data) throws -> Data {
        let sk = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        return Data(sk.publicKey.rawRepresentation)
    }

    /// Base58-encoded Solana address for a 32-byte public key.
    static func address(publicKey: Data) -> String {
        Base58.encode(publicKey)
    }

    /// Convenience: phrase → derive(seed: …, path: m/44'/501'/i'/0')
    /// → (address, 32-byte private key seed).
    static func keypair(
        fromMnemonic phrase: String,
        passphrase: String = "",
        account: UInt32 = 0
    ) throws -> (address: String, privateKey: Data) {
        let seed = try BIP39.mnemonicToSeed(phrase, passphrase: passphrase)
        let derived = try derive(seed: seed, path: solanaPath(account: account))
        let pub = try publicKey(privateKey: derived.privateKey)
        return (address: address(publicKey: pub), privateKey: derived.privateKey)
    }

    // MARK: - SLIP-0010

    /// HMAC-SHA512(key: "ed25519 seed", data: seed) → (IL, IR).
    /// IL is the master private key; IR is the master chain code.
    private static func masterKey(from seed: Data) -> DerivedKey {
        let key = SymmetricKey(data: Data("ed25519 seed".utf8))
        let mac = HMAC<SHA512>.authenticationCode(for: seed, using: key)
        let bytes = Data(mac)
        return DerivedKey(
            privateKey: Data(bytes.prefix(32)),
            chainCode: Data(bytes.suffix(32))
        )
    }

    /// Hardened child: I = HMAC-SHA512(key: parent.chainCode,
    /// data: 0x00 || parent.privateKey || index_be32). Only hardened
    /// (index has high bit set) is defined for ed25519 in SLIP-0010.
    private static func childKey(parent: DerivedKey, index: UInt32) -> DerivedKey {
        var buf = Data(count: 1 + 32 + 4)
        buf[0] = 0x00
        buf.replaceSubrange(1..<33, with: parent.privateKey)
        var be = index.bigEndian
        withUnsafeBytes(of: &be) { ptr in
            buf.replaceSubrange(33..<37, with: ptr)
        }
        let key = SymmetricKey(data: parent.chainCode)
        let mac = HMAC<SHA512>.authenticationCode(for: buf, using: key)
        let bytes = Data(mac)
        return DerivedKey(
            privateKey: Data(bytes.prefix(32)),
            chainCode: Data(bytes.suffix(32))
        )
    }

    enum Error: Swift.Error, LocalizedError {
        case badPath(String)
        case unhardenedSegment(String)

        var errorDescription: String? {
            switch self {
            case .badPath(let p):
                return "Invalid derivation path: \(p)"
            case .unhardenedSegment(let s):
                return "Segment \(s) must be hardened (end with `'`)."
            }
        }
    }

    /// Parse `m/44'/501'/0'/0'` → [0x8000002C, 0x800001F5, 0x80000000, 0x80000000].
    private static func parsePath(_ path: String) throws -> [UInt32] {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.first == "m" else { throw Error.badPath(path) }
        var out: [UInt32] = []
        for raw in parts.dropFirst() {
            guard raw.hasSuffix("'") else {
                throw Error.unhardenedSegment(raw)
            }
            let numberPart = String(raw.dropLast())
            guard let n = UInt32(numberPart) else {
                throw Error.badPath(path)
            }
            out.append(0x8000_0000 | n)
        }
        return out
    }
}

// MARK: - Base58

/// Bitcoin / Solana Base58 alphabet. The "1" is the leading-zero
/// stand-in; no 0/O/I/l to avoid ambiguity.
private enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func encode(_ bytes: Data) -> String {
        if bytes.isEmpty { return "" }
        // Long-division on a base-256 number → base-58 digits.
        var digits: [UInt8] = [0]
        for byte in bytes {
            var carry = Int(byte)
            for i in 0..<digits.count {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        // Preserve leading zero bytes as "1"s.
        var leadingZeros = 0
        for byte in bytes {
            if byte == 0 { leadingZeros += 1 } else { break }
        }
        var out = String(repeating: "1", count: leadingZeros)
        for digit in digits.reversed() {
            out.append(alphabet[Int(digit)])
        }
        return out
    }
}
