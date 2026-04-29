import Foundation

/// Hub serializes BIGINT TIDs as numbers when small enough and as
/// strings otherwise. All callers normalize to String so we don't
/// have to worry about JS's safe-integer range.
enum HubDecode {
    static func bigInt<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> String {
        if let s = try? container.decode(String.self, forKey: key) { return s }
        if let n = try? container.decode(Int64.self, forKey: key) { return String(n) }
        if let n = try? container.decode(Double.self, forKey: key) { return String(Int64(n)) }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected bigint-as-string"
        )
    }

    static func bigIntIfPresent<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> String? {
        guard container.contains(key) else { return nil }
        if try container.decodeNil(forKey: key) { return nil }
        return try bigInt(container, forKey: key)
    }

    /// Some hub rows return timestamps as ISO8601 strings, others as
    /// epoch seconds. Try both.
    static func date<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Date {
        if let iso = try? container.decode(String.self, forKey: key) {
            if let d = ISO8601DateFormatter.tribe.date(from: iso) { return d }
            if let d = ISO8601DateFormatter.tribePlain.date(from: iso) { return d }
        }
        if let n = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: n)
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Unrecognized timestamp"
        )
    }

    static func dateIfPresent<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Date? {
        guard container.contains(key) else { return nil }
        if try container.decodeNil(forKey: key) { return nil }
        return try? date(container, forKey: key)
    }

    static func intCount<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Int {
        if let i = try? container.decode(Int.self, forKey: key) { return i }
        if let s = try? container.decode(String.self, forKey: key), let i = Int(s) { return i }
        return 0
    }

    static func decimal<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Decimal {
        if let d = try? container.decode(Decimal.self, forKey: key) { return d }
        if let s = try? container.decode(String.self, forKey: key), let d = Decimal(string: s) { return d }
        if let n = try? container.decode(Double.self, forKey: key) { return Decimal(n) }
        return 0
    }
}
