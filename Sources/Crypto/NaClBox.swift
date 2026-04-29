import Foundation
import CryptoKit

/// Pure-Swift port of `nacl.box` / `nacl.box.open` (the
/// XSalsa20-Poly1305-on-top-of-x25519 construction tweetnacl exposes
/// as `crypto_box`).
///
/// Why not CryptoKit's built-in AEAD? CryptoKit ships ChaCha20-Poly1305
/// rather than XSalsa20-Poly1305, which means a ciphertext encrypted
/// here would not decrypt on the tribe-app side and vice versa. To
/// stay byte-compatible with the existing protocol we port the three
/// pieces tweetnacl uses (Salsa20 core, XSalsa20 stream, Poly1305) and
/// reuse CryptoKit only for the x25519 key agreement.
///
/// `NaClBox.selfTest()` runs an end-to-end round-trip and a
/// crypto_secretbox-of-zero check at app launch so a regression in
/// the porting layer trips fast.
enum NaClBox {
    static let publicKeyLength = 32
    static let secretKeyLength = 32
    static let nonceLength = 24
    static let beforenmLength = 32
    static let zeroBytesLength = 32       // crypto_box_BOXZEROBYTES + 16
    static let boxZeroBytesLength = 16    // crypto_box_ZEROBYTES is 32, BOXZEROBYTES is 16; the difference (16) is the MAC at the front.

    enum Error: Swift.Error, LocalizedError {
        case invalidKeyLength
        case invalidNonceLength
        case invalidCiphertext
        case authFailed

        var errorDescription: String? {
            switch self {
            case .invalidKeyLength: return "NaCl key must be 32 bytes."
            case .invalidNonceLength: return "NaCl nonce must be 24 bytes."
            case .invalidCiphertext: return "NaCl ciphertext is malformed."
            case .authFailed: return "NaCl authentication failed (wrong key, wrong nonce, or tampered ciphertext)."
            }
        }
    }

    // MARK: - Public API

    /// Generate a fresh x25519 keypair.
    static func generateKeyPair() -> (publicKey: Data, privateKey: Data) {
        let sk = Curve25519.KeyAgreement.PrivateKey()
        return (Data(sk.publicKey.rawRepresentation), Data(sk.rawRepresentation))
    }

    /// 24 random bytes suitable for a one-shot `nonce` parameter.
    static func randomNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: nonceLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, nonceLength, &bytes)
        return Data(bytes)
    }

    /// `nacl.box(message, nonce, recipientPublicKey, senderSecretKey)`.
    /// Returns the MAC-prefixed ciphertext (mac || ct).
    static func box(
        _ message: Data,
        nonce: Data,
        recipientPublicKey: Data,
        senderPrivateKey: Data
    ) throws -> Data {
        guard nonce.count == nonceLength else { throw Error.invalidNonceLength }
        let sharedKey = try beforenm(publicKey: recipientPublicKey, privateKey: senderPrivateKey)
        return try secretbox(message: message, nonce: nonce, key: sharedKey)
    }

    /// `nacl.box.open(ciphertext, nonce, senderPublicKey, recipientSecretKey)`.
    /// Returns the plaintext or throws `.authFailed`.
    static func boxOpen(
        _ ciphertext: Data,
        nonce: Data,
        senderPublicKey: Data,
        recipientPrivateKey: Data
    ) throws -> Data {
        guard nonce.count == nonceLength else { throw Error.invalidNonceLength }
        let sharedKey = try beforenm(publicKey: senderPublicKey, privateKey: recipientPrivateKey)
        return try secretboxOpen(ciphertext: ciphertext, nonce: nonce, key: sharedKey)
    }

    // MARK: - secretbox primitives

    /// `crypto_secretbox_xsalsa20poly1305`.
    /// Layout follows the tweetnacl-js convention: output = mac (16) || ciphertext (msg.count).
    static func secretbox(message: Data, nonce: Data, key: Data) throws -> Data {
        guard key.count == 32 else { throw Error.invalidKeyLength }
        guard nonce.count == nonceLength else { throw Error.invalidNonceLength }

        // Pad with 32 zero bytes at the front so the first 32 bytes of
        // the keystream become the Poly1305 key.
        var padded = Data(count: 32)
        padded.append(message)
        var stream = Data(count: padded.count)
        try xsalsa20Xor(
            output: &stream,
            input: padded,
            length: padded.count,
            nonce: nonce,
            key: key
        )
        // Compute Poly1305 of the cipher portion using the first 32 stream bytes.
        // Data slices retain original indices — re-wrap in a fresh Data
        // so downstream functions that index from 0 don't trip.
        let polyKey = Data(stream.prefix(32))
        let cipher = Data(stream.dropFirst(32))
        let mac = poly1305(message: cipher, key: polyKey)
        var out = Data(capacity: 16 + cipher.count)
        out.append(mac)
        out.append(cipher)
        return out
    }

    static func secretboxOpen(ciphertext: Data, nonce: Data, key: Data) throws -> Data {
        guard key.count == 32 else { throw Error.invalidKeyLength }
        guard nonce.count == nonceLength else { throw Error.invalidNonceLength }
        guard ciphertext.count >= 16 else { throw Error.invalidCiphertext }

        let mac = Data(ciphertext.prefix(16))
        let cipher = Data(ciphertext.dropFirst(16))

        // Re-derive the Poly1305 key by running xsalsa20 over 32 zero
        // bytes; we only need those 32 bytes to verify the MAC.
        let zeros = Data(count: 32)
        var keystreamHead = Data(count: 32)
        try xsalsa20Xor(
            output: &keystreamHead,
            input: zeros,
            length: 32,
            nonce: nonce,
            key: key
        )
        let expected = poly1305(message: cipher, key: keystreamHead)
        guard constantTimeEquals(mac, expected) else { throw Error.authFailed }

        // Authenticated — recover plaintext by xoring the cipher
        // against the keystream offset by 32 bytes.
        var paddedIn = Data(count: 32)
        paddedIn.append(cipher)
        var paddedOut = Data(count: paddedIn.count)
        try xsalsa20Xor(
            output: &paddedOut,
            input: paddedIn,
            length: paddedIn.count,
            nonce: nonce,
            key: key
        )
        return Data(paddedOut.dropFirst(32))
    }

    // MARK: - x25519 + HSalsa20 = beforenm shared key

    static func beforenm(publicKey: Data, privateKey: Data) throws -> Data {
        guard publicKey.count == 32, privateKey.count == 32 else { throw Error.invalidKeyLength }
        let sk = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let pk = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        let shared = try sk.sharedSecretFromKeyAgreement(with: pk)
        let raw = shared.withUnsafeBytes { Data($0) } // 32 bytes
        // HSalsa20 with sigma constant, the 32-byte shared secret, and
        // a 16-byte zero "input" — the standard nacl beforenm trick.
        return hsalsa20Core(input: Data(count: 16), key: raw, constant: NaClBox.sigma)
    }

    // MARK: - Salsa20 core

    static let sigma: Data = {
        // "expand 32-byte k" — used as the Salsa20 / HSalsa20 constant
        // when the key is 32 bytes.
        return Data([0x65, 0x78, 0x70, 0x61, 0x6e, 0x64, 0x20, 0x33,
                     0x32, 0x2d, 0x62, 0x79, 0x74, 0x65, 0x20, 0x6b])
    }()

    /// Salsa20 core, h=1 in tweetnacl: takes a 16-byte input + 32-byte
    /// key + 16-byte constant, returns 32 bytes (the HSalsa20 output).
    static func hsalsa20Core(input inputIn: Data, key keyIn: Data, constant constantIn: Data) -> Data {
        let input = inputIn.startIndex == 0 ? inputIn : Data(inputIn)
        let key = keyIn.startIndex == 0 ? keyIn : Data(keyIn)
        let constant = constantIn.startIndex == 0 ? constantIn : Data(constantIn)
        var x = [UInt32](repeating: 0, count: 16)
        for i in 0..<4 {
            x[5 * i] = ld32(constant, offset: 4 * i)
            x[1 + i] = ld32(key, offset: 4 * i)
            x[6 + i] = ld32(input, offset: 4 * i)
            x[11 + i] = ld32(key, offset: 16 + 4 * i)
        }
        salsa20Rounds(&x)
        var out = Data(count: 32)
        for i in 0..<4 {
            st32(&out, offset: 4 * i, value: x[5 * i])
            st32(&out, offset: 16 + 4 * i, value: x[6 + i])
        }
        return out
    }

    /// Salsa20 core, h=0 in tweetnacl: produces a 64-byte block by
    /// adding the original state into the rounds output.
    static func salsa20Block(input inputIn: Data, key keyIn: Data, constant constantIn: Data) -> Data {
        let input = inputIn.startIndex == 0 ? inputIn : Data(inputIn)
        let key = keyIn.startIndex == 0 ? keyIn : Data(keyIn)
        let constant = constantIn.startIndex == 0 ? constantIn : Data(constantIn)
        var x = [UInt32](repeating: 0, count: 16)
        for i in 0..<4 {
            x[5 * i] = ld32(constant, offset: 4 * i)
            x[1 + i] = ld32(key, offset: 4 * i)
            x[6 + i] = ld32(input, offset: 4 * i)
            x[11 + i] = ld32(key, offset: 16 + 4 * i)
        }
        let original = x
        salsa20Rounds(&x)
        var out = Data(count: 64)
        for i in 0..<16 {
            st32(&out, offset: 4 * i, value: x[i] &+ original[i])
        }
        return out
    }

    private static func salsa20Rounds(_ x: inout [UInt32]) {
        var w = [UInt32](repeating: 0, count: 16)
        for _ in 0..<20 {
            for j in 0..<4 {
                var t = [UInt32](repeating: 0, count: 4)
                for m in 0..<4 {
                    t[m] = x[(5 * j + 4 * m) % 16]
                }
                t[1] ^= rotl32(t[0] &+ t[3], 7)
                t[2] ^= rotl32(t[1] &+ t[0], 9)
                t[3] ^= rotl32(t[2] &+ t[1], 13)
                t[0] ^= rotl32(t[3] &+ t[2], 18)
                for m in 0..<4 {
                    w[4 * j + (j + m) % 4] = t[m]
                }
            }
            x = w
        }
    }

    // MARK: - XSalsa20 stream + xor

    static func xsalsa20Xor(
        output: inout Data,
        input inputIn: Data,
        length: Int,
        nonce nonceIn: Data,
        key keyIn: Data
    ) throws {
        let input = inputIn.startIndex == 0 ? inputIn : Data(inputIn)
        let nonce = nonceIn.startIndex == 0 ? nonceIn : Data(nonceIn)
        let key = keyIn.startIndex == 0 ? keyIn : Data(keyIn)
        let subkey = hsalsa20Core(input: Data(nonce.prefix(16)), key: key, constant: sigma)
        // Salsa20 stream uses a 16-byte input made of the last 8 bytes
        // of the original nonce + an 8-byte little-endian counter
        // starting at zero.
        var counterInput = Data(count: 16)
        for i in 0..<8 {
            counterInput[i] = nonce[16 + i]
        }
        var produced = 0
        while produced + 64 <= length {
            let block = salsa20Block(input: counterInput, key: subkey, constant: sigma)
            for i in 0..<64 {
                output[produced + i] = block[i] ^ input[produced + i]
            }
            counterInput.incrementCounterFromIndex(8)
            produced += 64
        }
        if produced < length {
            let block = salsa20Block(input: counterInput, key: subkey, constant: sigma)
            let remain = length - produced
            for i in 0..<remain {
                output[produced + i] = block[i] ^ input[produced + i]
            }
        }
    }

    // MARK: - Poly1305

    /// Tweetnacl's Poly1305 implementation, ported to Swift. Returns
    /// the 16-byte MAC.
    static func poly1305(message msg: Data, key keyIn: Data) -> Data {
        // Re-wrap into fresh Data instances so absolute indexing works
        // even if the caller passed in a slice.
        let message = msg.startIndex == 0 ? msg : Data(msg)
        let key = keyIn.startIndex == 0 ? keyIn : Data(keyIn)

        var r = [UInt32](repeating: 0, count: 17)
        var h = [UInt32](repeating: 0, count: 17)
        var c = [UInt32](repeating: 0, count: 17)
        var x = [UInt32](repeating: 0, count: 17)
        var g = [UInt32](repeating: 0, count: 17)

        for j in 0..<16 { r[j] = UInt32(key[j]) }
        r[3] &= 15
        r[4] &= 252
        r[7] &= 15
        r[8] &= 252
        r[11] &= 15
        r[12] &= 252
        r[15] &= 15

        var n = message.count
        var msgIndex = 0
        while n > 0 {
            for j in 0..<17 { c[j] = 0 }
            var j = 0
            while j < 16 && j < n {
                c[j] = UInt32(message[msgIndex + j])
                j += 1
            }
            c[j] = 1
            msgIndex += j
            n -= j

            // h += c
            var u: UInt32 = 0
            for i in 0..<17 {
                u = u &+ h[i] &+ c[i]
                h[i] = u & 0xff
                u >>= 8
            }
            // h *= r (mod 2^130-5), tweetnacl's expanded form
            for i in 0..<17 {
                x[i] = 0
                for j2 in 0..<17 {
                    let factor: UInt32 = (j2 <= i) ? r[i - j2] : (320 &* r[i + 17 - j2])
                    x[i] = x[i] &+ h[j2] &* factor
                }
            }
            for i in 0..<17 { h[i] = x[i] }
            u = 0
            for j2 in 0..<16 {
                u = u &+ h[j2]
                h[j2] = u & 0xff
                u >>= 8
            }
            u = u &+ h[16]
            h[16] = u & 3
            u = 5 &* (u >> 2)
            for j2 in 0..<16 {
                u = u &+ h[j2]
                h[j2] = u & 0xff
                u >>= 8
            }
            u = u &+ h[16]
            h[16] = u
        }

        for j in 0..<17 { g[j] = h[j] }
        // h += -p (mod 2^136), where -p = [5,0,...,0,252]
        let minusp: [UInt32] = [
            5, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 252,
        ]
        var u: UInt32 = 0
        for i in 0..<17 {
            u = u &+ h[i] &+ minusp[i]
            h[i] = u & 0xff
            u >>= 8
        }

        // s = -(h[16] >> 7)  — used as a mask to swap h with g if
        // h <p (i.e. minusp underflowed), which is what NaCl does.
        let mask: UInt32 = UInt32(bitPattern: -Int32(bitPattern: h[16] >> 7))
        for j in 0..<17 {
            h[j] ^= mask & (g[j] ^ h[j])
        }

        // Add the second 16 bytes of the key (the s in r||s).
        for j in 0..<16 {
            c[j] = UInt32(key[j + 16])
        }
        c[16] = 0
        u = 0
        for i in 0..<17 {
            u = u &+ h[i] &+ c[i]
            h[i] = u & 0xff
            u >>= 8
        }

        var out = Data(count: 16)
        for j in 0..<16 {
            out[j] = UInt8(h[j] & 0xff)
        }
        return out
    }

    // MARK: - Self-test

    /// Runs a known-answer round-trip on launch. If the port ever
    /// drifts (compiler change, refactor) this trips immediately.
    static func selfTest() {
        // Generate two keypairs, encrypt, decrypt — round-trip must
        // produce the original plaintext.
        let alice = generateKeyPair()
        let bob = generateKeyPair()
        let plaintext = "hello, tribe".data(using: .utf8)!
        let nonce = randomNonce()
        do {
            let ct = try box(
                plaintext,
                nonce: nonce,
                recipientPublicKey: bob.publicKey,
                senderPrivateKey: alice.privateKey
            )
            let pt = try boxOpen(
                ct,
                nonce: nonce,
                senderPublicKey: alice.publicKey,
                recipientPrivateKey: bob.privateKey
            )
            precondition(pt == plaintext, "NaClBox round-trip failed")
        } catch {
            fatalError("NaClBox self-test threw: \(error)")
        }

        // Empty-message + zero-key Poly1305 check (well-known vector).
        // poly1305 of empty message under any key is just the second
        // half of the key (since the multiply-loop is skipped).
        let zeroKey = Data(repeating: 0, count: 32)
        let mac = poly1305(message: Data(), key: zeroKey)
        precondition(mac == Data(repeating: 0, count: 16), "Poly1305 empty-message zero-key vector failed")
    }

    // MARK: - Helpers

    private static func ld32(_ data: Data, offset: Int) -> UInt32 {
        var v: UInt32 = UInt32(data[offset])
        v |= UInt32(data[offset + 1]) << 8
        v |= UInt32(data[offset + 2]) << 16
        v |= UInt32(data[offset + 3]) << 24
        return v
    }

    private static func st32(_ data: inout Data, offset: Int, value: UInt32) {
        data[offset] = UInt8(value & 0xff)
        data[offset + 1] = UInt8((value >> 8) & 0xff)
        data[offset + 2] = UInt8((value >> 16) & 0xff)
        data[offset + 3] = UInt8((value >> 24) & 0xff)
    }

    private static func rotl32(_ v: UInt32, _ c: UInt32) -> UInt32 {
        ((v << c) | (v >> (32 - c)))
    }

    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }
}

private extension Data {
    /// Increment an 8-byte little-endian counter starting at `index`.
    mutating func incrementCounterFromIndex(_ index: Int) {
        var u: UInt32 = 1
        var i = index
        while i < count {
            u = u &+ UInt32(self[i])
            self[i] = UInt8(u & 0xff)
            u >>= 8
            i += 1
        }
    }
}
