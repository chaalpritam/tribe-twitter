import Foundation

/// Pure-Swift port of the BLAKE3 reference implementation
/// (https://github.com/BLAKE3-team/BLAKE3/blob/master/reference_impl/reference_impl.rs).
///
/// We need this because CryptoKit doesn't ship BLAKE3 and pulling in a
/// SwiftPM dependency just for one hash isn't worth the build-time cost.
///
/// The protocol only ever hashes envelope payloads (under a few KB), so
/// performance isn't a concern — correctness matched against the
/// official test vectors is. A handful of vectors run inside `Blake3.selfTest()`
/// at process start and trap on mismatch.
enum Blake3 {
    static let outputLength = 32

    // MARK: - Constants

    private static let IV: [UInt32] = [
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
    ]

    private static let MSG_PERMUTATION: [Int] = [
        2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8,
    ]

    private static let CHUNK_START: UInt32 = 1 << 0
    private static let CHUNK_END: UInt32 = 1 << 1
    private static let PARENT: UInt32 = 1 << 2
    private static let ROOT: UInt32 = 1 << 3

    private static let CHUNK_LEN = 1024
    private static let BLOCK_LEN = 64

    // MARK: - Public API

    /// 32-byte BLAKE3 hash. Equivalent to `blake3.hash(input).digest`
    /// in the JS / Python reference.
    static func hash(_ input: Data) -> Data {
        var hasher = Hasher()
        hasher.update(input)
        return hasher.finalize()
    }

    // MARK: - Compression

    private static func g(_ state: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ mx: UInt32, _ my: UInt32) {
        state[a] = state[a] &+ state[b] &+ mx
        state[d] = (state[d] ^ state[a]).rotatedRight(16)
        state[c] = state[c] &+ state[d]
        state[b] = (state[b] ^ state[c]).rotatedRight(12)
        state[a] = state[a] &+ state[b] &+ my
        state[d] = (state[d] ^ state[a]).rotatedRight(8)
        state[c] = state[c] &+ state[d]
        state[b] = (state[b] ^ state[c]).rotatedRight(7)
    }

    private static func roundFn(_ state: inout [UInt32], _ m: [UInt32]) {
        // Mix the columns.
        g(&state, 0, 4, 8, 12, m[0], m[1])
        g(&state, 1, 5, 9, 13, m[2], m[3])
        g(&state, 2, 6, 10, 14, m[4], m[5])
        g(&state, 3, 7, 11, 15, m[6], m[7])
        // Mix the diagonals.
        g(&state, 0, 5, 10, 15, m[8], m[9])
        g(&state, 1, 6, 11, 12, m[10], m[11])
        g(&state, 2, 7, 8, 13, m[12], m[13])
        g(&state, 3, 4, 9, 14, m[14], m[15])
    }

    private static func permute(_ m: inout [UInt32]) {
        var permuted = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 { permuted[i] = m[MSG_PERMUTATION[i]] }
        m = permuted
    }

    private static func compress(
        chainingValue: [UInt32],
        blockWords: [UInt32],
        counter: UInt64,
        blockLen: UInt32,
        flags: UInt32
    ) -> [UInt32] {
        var state: [UInt32] = [
            chainingValue[0], chainingValue[1], chainingValue[2], chainingValue[3],
            chainingValue[4], chainingValue[5], chainingValue[6], chainingValue[7],
            IV[0], IV[1], IV[2], IV[3],
            UInt32(truncatingIfNeeded: counter),
            UInt32(truncatingIfNeeded: counter >> 32),
            blockLen,
            flags,
        ]
        var block = blockWords
        roundFn(&state, block); permute(&block)
        roundFn(&state, block); permute(&block)
        roundFn(&state, block); permute(&block)
        roundFn(&state, block); permute(&block)
        roundFn(&state, block); permute(&block)
        roundFn(&state, block); permute(&block)
        roundFn(&state, block) // round 7, no permute after

        for i in 0..<8 {
            state[i] ^= state[i + 8]
            state[i + 8] ^= chainingValue[i]
        }
        return state
    }

    private static func wordsFromBlock(_ block: Data) -> [UInt32] {
        precondition(block.count == BLOCK_LEN, "block must be 64 bytes")
        var words = [UInt32](repeating: 0, count: 16)
        block.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<16 {
                let p = base.advanced(by: i * 4)
                words[i] = UInt32(p[0])
                    | (UInt32(p[1]) << 8)
                    | (UInt32(p[2]) << 16)
                    | (UInt32(p[3]) << 24)
            }
        }
        return words
    }

    // MARK: - Chunk state

    private struct ChunkState {
        var chainingValue: [UInt32]
        var chunkCounter: UInt64
        var block: Data = Data()
        var blocksCompressed: UInt32 = 0
        var flags: UInt32

        init(key: [UInt32], chunkCounter: UInt64, flags: UInt32) {
            self.chainingValue = key
            self.chunkCounter = chunkCounter
            self.flags = flags
        }

        var len: Int { Blake3.BLOCK_LEN * Int(blocksCompressed) + block.count }

        var startFlag: UInt32 {
            blocksCompressed == 0 ? Blake3.CHUNK_START : 0
        }

        mutating func update(_ input: Data) {
            var input = input
            while !input.isEmpty {
                if block.count == Blake3.BLOCK_LEN {
                    let words = Blake3.wordsFromBlock(block)
                    chainingValue = Array(Blake3.compress(
                        chainingValue: chainingValue,
                        blockWords: words,
                        counter: chunkCounter,
                        blockLen: UInt32(Blake3.BLOCK_LEN),
                        flags: flags | startFlag
                    ).prefix(8))
                    blocksCompressed += 1
                    block.removeAll(keepingCapacity: true)
                }
                let want = Blake3.BLOCK_LEN - block.count
                let take = min(want, input.count)
                block.append(input.prefix(take))
                input = input.advanced(by: take)
            }
        }

        func output() -> Output {
            let blockLen = block.count
            var lastBlock = block
            if lastBlock.count < Blake3.BLOCK_LEN {
                lastBlock.append(Data(repeating: 0, count: Blake3.BLOCK_LEN - lastBlock.count))
            }
            return Output(
                inputChainingValue: chainingValue,
                blockWords: Blake3.wordsFromBlock(lastBlock),
                counter: chunkCounter,
                blockLen: UInt32(blockLen),
                flags: flags | startFlag | Blake3.CHUNK_END
            )
        }
    }

    // MARK: - Output

    private struct Output {
        let inputChainingValue: [UInt32]
        let blockWords: [UInt32]
        let counter: UInt64
        let blockLen: UInt32
        let flags: UInt32

        func chainingValue() -> [UInt32] {
            Array(Blake3.compress(
                chainingValue: inputChainingValue,
                blockWords: blockWords,
                counter: counter,
                blockLen: blockLen,
                flags: flags
            ).prefix(8))
        }

        func rootOutputBytes(_ length: Int) -> Data {
            var out = Data()
            var counter: UInt64 = 0
            while out.count < length {
                let words = Blake3.compress(
                    chainingValue: inputChainingValue,
                    blockWords: blockWords,
                    counter: counter,
                    blockLen: blockLen,
                    flags: flags | Blake3.ROOT
                )
                for word in words {
                    var le = word.littleEndian
                    withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
                    if out.count >= length { break }
                }
                counter += 1
            }
            return out.prefix(length)
        }
    }

    // MARK: - Hasher (multi-chunk tree)

    struct Hasher {
        private var chunkState: ChunkState
        private var key: [UInt32]
        private var cvStack: [[UInt32]] = []
        private var cvStackLen: UInt8 = 0
        private var flags: UInt32

        init() {
            self.key = Blake3.IV
            self.flags = 0
            self.chunkState = ChunkState(key: Blake3.IV, chunkCounter: 0, flags: 0)
        }

        private mutating func parentOutput(left: [UInt32], right: [UInt32]) -> Output {
            let blockWords = left + right
            return Output(
                inputChainingValue: key,
                blockWords: blockWords,
                counter: 0,
                blockLen: UInt32(Blake3.BLOCK_LEN),
                flags: Blake3.PARENT | flags
            )
        }

        private mutating func parentCV(left: [UInt32], right: [UInt32]) -> [UInt32] {
            parentOutput(left: left, right: right).chainingValue()
        }

        private mutating func pushCV(_ cv: [UInt32], chunkCounter: UInt64) {
            var newCV = cv
            var totalChunks = chunkCounter + 1
            while totalChunks & 1 == 0 {
                let popped = cvStack.removeLast()
                cvStackLen -= 1
                newCV = parentCV(left: popped, right: newCV)
                totalChunks >>= 1
            }
            cvStack.append(newCV)
            cvStackLen += 1
        }

        mutating func update(_ input: Data) {
            var input = input
            while !input.isEmpty {
                if chunkState.len == Blake3.CHUNK_LEN {
                    let cv = chunkState.output().chainingValue()
                    let counter = chunkState.chunkCounter
                    pushCV(cv, chunkCounter: counter)
                    chunkState = ChunkState(key: key, chunkCounter: counter + 1, flags: flags)
                }
                let want = Blake3.CHUNK_LEN - chunkState.len
                let take = min(want, input.count)
                chunkState.update(input.prefix(take))
                input = input.advanced(by: take)
            }
        }

        func finalize(_ length: Int = Blake3.outputLength) -> Data {
            var output = chunkState.output()
            var stack = cvStack
            // Roll up any remaining stacked subtrees as right children of
            // the current chunk's output.
            while !stack.isEmpty {
                let popped = stack.removeLast()
                output = Output(
                    inputChainingValue: key,
                    blockWords: popped + output.chainingValue(),
                    counter: 0,
                    blockLen: UInt32(Blake3.BLOCK_LEN),
                    flags: Blake3.PARENT | flags
                )
            }
            return output.rootOutputBytes(length)
        }
    }

    // MARK: - Self-test

    /// Trapping self-test against the official BLAKE3 reference vectors
    /// (https://github.com/BLAKE3-team/BLAKE3/blob/master/test_vectors/test_vectors.json).
    /// Called once during AppState init; if Apple ever changes a Swift
    /// integer behaviour out from under us we fail loudly at startup
    /// instead of silently producing rejected envelopes.
    static func selfTest() {
        // Empty input.
        let empty = hash(Data())
        let emptyExpected = "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
        precondition(empty.hex == emptyExpected, "Blake3 empty vector failed: \(empty.hex)")

        // 1-byte input: 0x00.
        let oneByte = hash(Data([0x00]))
        let oneByteExpected = "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213"
        precondition(oneByte.hex == oneByteExpected, "Blake3 1-byte vector failed: \(oneByte.hex)")

        // 1023-byte input (cycles 0..250 inclusive).
        var seq = Data()
        for i in 0..<1023 { seq.append(UInt8(i % 251)) }
        let nearChunk = hash(seq)
        let nearChunkExpected = "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11"
        precondition(nearChunk.hex == nearChunkExpected, "Blake3 1023-byte vector failed: \(nearChunk.hex)")
    }
}

// MARK: - Helpers

private extension UInt32 {
    func rotatedRight(_ n: UInt32) -> UInt32 {
        (self >> n) | (self << (32 - n))
    }
}

extension Data {
    /// Lowercase-hex representation. Used for test-vector comparison and
    /// debug logging — the protocol uses base64 on the wire, not hex.
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Subdata starting at an offset, returning a new Data instance with
    /// indices reset to zero. The default `Data.advanced(by:)` keeps the
    /// original index space, which surprises every loop that uses
    /// `Data` like a slice.
    func advanced(by offset: Int) -> Data {
        Data(self.suffix(from: self.startIndex + offset))
    }
}
