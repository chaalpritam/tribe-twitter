import Foundation

/// Hub validates channel / poll / event / task / crowdfund IDs against
/// `^[a-z0-9-]{1,64}$`. We slug the user's free-form title client-side
/// the same way tribe-app does in `src/lib/messages.ts`, then suffix
/// 6 random hex chars so the same title can be reused without
/// colliding with an existing row.
enum Slug {
    static func make(_ input: String, randomSuffixLength: Int = 6) -> String {
        let lowered = input.lowercased()
        var stripped = ""
        stripped.reserveCapacity(lowered.count)
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                stripped.append(ch)
            } else if ch == " " || ch == "-" || ch == "_" {
                stripped.append("-")
            }
        }
        // Collapse runs of dashes and trim leading / trailing dashes.
        while stripped.contains("--") {
            stripped = stripped.replacingOccurrences(of: "--", with: "-")
        }
        stripped = stripped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if stripped.isEmpty { stripped = "tribe" }

        let suffix = randomHex(randomSuffixLength)
        let combined = "\(stripped)-\(suffix)"
        // Hub maxes at 64 chars; trim from the front of the slug body
        // if needed so the random suffix survives.
        if combined.count > 64 {
            let dropAmount = combined.count - 64
            let body = String(stripped.dropFirst(dropAmount))
            return "\(body)-\(suffix)"
        }
        return combined
    }

    private static func randomHex(_ count: Int) -> String {
        let bytes = (0..<count).map { _ in UInt8.random(in: 0..<16) }
        return bytes.map { String($0, radix: 16) }.joined()
    }
}
