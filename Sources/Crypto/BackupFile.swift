import Foundation
import CryptoKit
import CommonCrypto

/// Versioned account backup. Byte-for-byte compatible with tribe-app's
/// `.tribe` / `.tribe.enc` format (see `tribe-app/src/lib/backup.ts`),
/// so files exported here can be imported there and vice versa.
///
/// Plain form: pretty-printed JSON of this struct.
///
/// Encrypted form (`.tribe.enc`): AES-256-GCM with a key derived via
/// PBKDF2(SHA-256, 100k iters) from a user-supplied password. Wire
/// layout is base64( salt[16] || nonce[12] || ciphertext || tag[16] )
/// — matching the layout `window.crypto.subtle` produces on the web.
struct BackupFile: Codable, Equatable {
    let version: Int
    let timestamp: Int64
    let data: Payload

    /// One nullable string per slot. Required slots (tid, appKeySecret)
    /// are still typed as optional because we want to surface a
    /// validation error rather than fail to decode an otherwise
    /// well-formed file.
    struct Payload: Codable, Equatable {
        let tid: String?
        let tidWallet: String?
        let appKeySecret: String?
        let browserWallet: String?
        let dmKeypair: String?
    }

    static let currentVersion = 1

    static let saltSize = 16
    static let nonceSize = 12
    static let tagSize = 16
    static let pbkdf2Iterations = 100_000
    static let aesKeyLength = 32

    /// Build a payload from in-memory state. tribe-app expects the
    /// app-key secret as the 64-byte nacl ed25519 secretKey (seed ||
    /// pubkey), and the DM keypair as a JSON object of two 32-byte
    /// base64 strings.
    static func build(
        tid: String?,
        walletAddress: String?,
        appKey: AppKey?,
        dmKey: DMKey?,
        browserWalletJSON: String?
    ) -> BackupFile {
        let appKeySecretB64: String? = appKey.map { key in
            var combined = Data()
            combined.append(key.privateKey.rawRepresentation)
            combined.append(key.publicKey.rawRepresentation)
            return combined.base64EncodedString()
        }
        let dmKeypairJSON: String? = dmKey.map { dm in
            let blob: [String: String] = [
                "publicKey": dm.publicKey.base64EncodedString(),
                "secretKey": dm.privateKey.base64EncodedString(),
            ]
            return Self.jsonString(blob)
        }
        return BackupFile(
            version: currentVersion,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            data: Payload(
                tid: tid,
                tidWallet: walletAddress,
                appKeySecret: appKeySecretB64,
                browserWallet: browserWalletJSON,
                dmKeypair: dmKeypairJSON
            )
        )
    }

    // MARK: - Encoding / decoding

    /// JSON bytes of the plain (`.tribe`) form. Pretty-printed and
    /// sorted-keys so diffs against tribe-app exports stay small.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Base64 string of the encrypted (`.tribe.enc`) form.
    func encrypted(password: String) throws -> String {
        let payload = try encoded()
        let salt = Self.randomBytes(Self.saltSize)
        let keyBytes = try Self.pbkdf2(
            password: password,
            salt: salt,
            iterations: Self.pbkdf2Iterations,
            keyLength: Self.aesKeyLength
        )
        let symmetric = SymmetricKey(data: keyBytes)
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(payload, using: symmetric)
        } catch {
            throw BackupError.encryptionFailed
        }
        guard let combined = sealed.combined else {
            throw BackupError.encryptionFailed
        }
        var out = Data()
        out.append(salt)
        out.append(combined)
        return out.base64EncodedString()
    }

    /// Parse a file's text contents, decrypting if needed. Pass nil
    /// password for plain files.
    static func decode(text: String, password: String?) throws -> BackupFile {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEncrypted(trimmed) {
            guard let password, !password.isEmpty else {
                throw BackupError.wrongPassword
            }
            guard
                let combined = Data(
                    base64Encoded: trimmed,
                    options: [.ignoreUnknownCharacters]
                ),
                combined.count > saltSize + nonceSize + tagSize
            else {
                throw BackupError.invalidBase64
            }
            let salt = Data(combined.prefix(saltSize))
            let sealedCombined = Data(combined.suffix(from: saltSize))
            let keyBytes = try pbkdf2(
                password: password,
                salt: salt,
                iterations: pbkdf2Iterations,
                keyLength: aesKeyLength
            )
            let symmetric = SymmetricKey(data: keyBytes)
            let sealed: AES.GCM.SealedBox
            do {
                sealed = try AES.GCM.SealedBox(combined: sealedCombined)
            } catch {
                throw BackupError.invalidBase64
            }
            let plaintext: Data
            do {
                plaintext = try AES.GCM.open(sealed, using: symmetric)
            } catch {
                throw BackupError.wrongPassword
            }
            return try parseJSON(plaintext)
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw BackupError.invalidJSON
        }
        return try parseJSON(data)
    }

    /// Heuristic from tribe-app: encrypted blobs are base64 (no
    /// leading `{`). Plain backups are JSON. Trying JSON.parse first
    /// is more reliable than relying on the file extension because
    /// users can rename `.tribe` ↔ `.tribe.enc` at will.
    static func isEncrypted(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return false }
        if trimmed.isEmpty { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=\n\r ")
        return trimmed.allSatisfy { allowed.contains($0) }
    }

    private static func parseJSON(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        let backup: BackupFile
        do {
            backup = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.invalidJSON
        }
        guard backup.version == currentVersion else {
            throw BackupError.unsupportedVersion(backup.version)
        }
        return backup
    }

    // MARK: - Internals

    private static func jsonString(_ object: [String: String]) -> String {
        // Sorted keys keep cross-platform diffs deterministic.
        let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static func pbkdf2(
        password: String,
        salt: Data,
        iterations: Int,
        keyLength: Int
    ) throws -> Data {
        var derived = Data(count: keyLength)
        let utf8Count = password.utf8.count
        let status: Int32 = password.withCString { passwordPtr in
            derived.withUnsafeMutableBytes { derivedBuf in
                guard let derivedPtr = derivedBuf.baseAddress?
                    .assumingMemoryBound(to: UInt8.self)
                else { return Int32(kCCParamError) }
                return salt.withUnsafeBytes { saltBuf -> Int32 in
                    guard let saltPtr = saltBuf.baseAddress?
                        .assumingMemoryBound(to: UInt8.self)
                    else { return Int32(kCCParamError) }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr, utf8Count,
                        saltPtr, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedPtr, keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw BackupError.encryptionFailed }
        return derived
    }

    private static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status: Int32 = data.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return -1 }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return data
    }
}

extension BackupFile {
    /// Write the backup's secrets into the iOS Keychain and return
    /// the parsed identity the caller should pass to `AppState.adopt`.
    /// Throws `missingFields` if tid + app-key aren't both present —
    /// without those two, the rest of the payload is unusable.
    func apply() throws -> (tid: String, appKey: AppKey, walletAddress: String?) {
        guard let tid = data.tid, !tid.isEmpty,
              let appKeyB64 = data.appKeySecret, !appKeyB64.isEmpty
        else {
            throw BackupError.missingFields
        }
        let appKey: AppKey
        do {
            appKey = try AppKey.restore(seedBase64: appKeyB64)
        } catch {
            throw BackupError.invalidAppKey
        }

        // DM key is optional — older tribe-app installs may not have
        // a per-TID slot if the user never opened DMs. Best-effort:
        // surface a decoding error only if the field is present but
        // malformed.
        if let dmRaw = data.dmKeypair, !dmRaw.isEmpty {
            guard let seed = Self.extractDmSeed(from: dmRaw) else {
                throw BackupError.invalidDMKey
            }
            try? KeychainStore.save(seed, for: .dmKeySeed)
        }

        // browserWallet is opaque on iOS — kept around so a later
        // export reproduces a file that still works in tribe-app.
        if let bw = data.browserWallet, !bw.isEmpty,
           let bwData = bw.data(using: .utf8) {
            try? KeychainStore.save(bwData, for: .browserWallet)
        }

        return (tid: tid, appKey: appKey, walletAddress: data.tidWallet)
    }

    /// Pull the 32-byte x25519 seed out of either the tribe-app JSON
    /// envelope (`{"publicKey": b64, "secretKey": b64}`) or a raw
    /// base64 of the secret. The 64-byte form (legacy nacl secretKey
    /// = seed || pubkey) folds to the first 32 bytes.
    private static func extractDmSeed(from raw: String) -> Data? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let jsonData = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let secret = json["secretKey"] as? String,
           let bytes = Data(base64Encoded: secret) {
            return Self.foldToSeed(bytes)
        }
        if let bytes = Data(base64Encoded: trimmed) {
            return Self.foldToSeed(bytes)
        }
        return nil
    }

    private static func foldToSeed(_ bytes: Data) -> Data? {
        switch bytes.count {
        case 32: return bytes
        case 64: return Data(bytes.prefix(32))
        default: return nil
        }
    }

    /// Read the opaque browser-wallet blob retained from a prior
    /// import. Returns nil when nothing was stored — fine; the
    /// emitted backup just leaves the field null.
    static func storedBrowserWalletJSON() -> String? {
        guard let raw = try? KeychainStore.load(.browserWallet),
              let str = String(data: raw, encoding: .utf8)
        else { return nil }
        return str
    }
}

enum BackupError: LocalizedError {
    case invalidBase64
    case invalidJSON
    case unsupportedVersion(Int)
    case missingFields
    case invalidAppKey
    case invalidDMKey
    case wrongPassword
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidBase64:
            return "Backup file isn't valid base64."
        case .invalidJSON:
            return "Backup file isn't valid JSON."
        case .unsupportedVersion(let v):
            return "Unsupported backup version (v\(v))."
        case .missingFields:
            return "Backup is missing the TID or app key — restoring it would leave the account unrecoverable."
        case .invalidAppKey:
            return "App key in the backup isn't valid."
        case .invalidDMKey:
            return "DM key in the backup isn't valid."
        case .wrongPassword:
            return "Wrong password, or the file is corrupted."
        case .encryptionFailed:
            return "Encryption failed."
        }
    }
}
