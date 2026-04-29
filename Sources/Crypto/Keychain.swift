import Foundation
import Security

/// Thin wrapper around the iOS Keychain for storing the user's
/// 32-byte ed25519 app-key seed. UserDefaults is the right place for
/// preferences (hub URL, current TID); the secret signing material
/// has to live in the Keychain so a backup of the device or another
/// app on the device can't read it.
enum KeychainStore {
    enum Key: String {
        /// Raw 32-byte ed25519 seed used to sign every envelope.
        case appKeySeed = "tribe.appKey.seed"
    }

    enum Error: Swift.Error {
        case unhandled(OSStatus)
        case decoding
    }

    private static let service = "app.tribe.ios"

    static func save(_ data: Data, for key: Key) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.unhandled(status) }
    }

    static func load(_ key: Key) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw Error.decoding }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw Error.unhandled(status)
        }
    }

    static func delete(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.unhandled(status)
        }
    }
}
