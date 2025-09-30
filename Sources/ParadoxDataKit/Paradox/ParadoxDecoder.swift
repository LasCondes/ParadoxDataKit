import Foundation

public protocol ParadoxCodingKey {
    var aliases: [String] { get }
}

public extension ParadoxCodingKey where Self: CodingKey {
    var aliases: [String] { [stringValue] }
}

public struct ParadoxDecoder: Decoder {
    public let snapshot: FieldSnapshot
    public let codingPath: [any CodingKey]
    public let userInfo: [CodingUserInfoKey: Any] = [:]

    public init(record: ParadoxRecord, codingPath: [any CodingKey] = []) {
        self.snapshot = FieldSnapshot(record: record)
        self.codingPath = codingPath
    }

    public static func decode<T: Decodable>(_ type: T.Type, from record: ParadoxRecord) throws -> T {
        try T(from: ParadoxDecoder(record: record))
    }

    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        KeyedDecodingContainer(KeyedContainer(decoder: self, codingPath: codingPath))
    }

    public func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, DecodingError.Context(codingPath: codingPath, debugDescription: "ParadoxDecoder supports keyed containers only."))
    }

    public func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw DecodingError.typeMismatch(Any.self, DecodingError.Context(codingPath: codingPath, debugDescription: "ParadoxDecoder supports keyed containers only."))
    }
}

public extension KeyedDecodingContainer {
    func decodeTrimmedString(forKey key: Key) throws -> String? {
        if let raw = try decodeIfPresent(String.self, forKey: key) {
            return FieldSnapshot.trimmedOrNil(raw)
        }
        return nil
    }
}

private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: ParadoxDecoder
    let codingPath: [any CodingKey]

    init(decoder: ParadoxDecoder, codingPath: [any CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
    }

    var allKeys: [Key] {
        []
    }

    private func candidates(for key: Key) -> [FieldSnapshot.NormalizedName] {
        if let aliasKey = key as? any ParadoxCodingKey {
            return aliasKey.aliases.map(FieldSnapshot.normalizeKey)
        }
        return key.stringValue
            .split(separator: "|")
            .map { FieldSnapshot.normalizeKey(String($0)) }
    }

    private func lookup(for key: Key) -> ParadoxValue?? {
        for candidate in candidates(for: key) {
            if let value = decoder.snapshot.value(forNormalizedName: candidate) {
                return value
            }
        }
        return nil
    }

    private func requireValue<T>(_ value: T?, for key: Key) throws -> T {
        guard let value else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Missing value for \(key.stringValue)"))
        }
        return value
    }

    func contains(_ key: Key) -> Bool {
        candidates(for: key).contains { decoder.snapshot.contains($0) }
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let entry = lookup(for: key) else { return true }
        return entry == nil
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try requireValue(decoder.snapshot.string(for: candidates(for: key)), for: key)
    }

    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? {
        decoder.snapshot.string(for: candidates(for: key))
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try requireValue(decoder.snapshot.double(for: candidates(for: key)), for: key)
    }

    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? {
        decoder.snapshot.double(for: candidates(for: key))
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try requireValue(decoder.snapshot.int(for: candidates(for: key)), for: key)
    }

    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? {
        decoder.snapshot.int(for: candidates(for: key))
    }

    func decode(_ type: Decimal.Type, forKey key: Key) throws -> Decimal {
        try requireValue(decoder.snapshot.decimal(for: candidates(for: key)), for: key)
    }

    func decodeIfPresent(_ type: Decimal.Type, forKey key: Key) throws -> Decimal? {
        decoder.snapshot.decimal(for: candidates(for: key))
    }

    func decode(_ type: Date.Type, forKey key: Key) throws -> Date {
        try requireValue(decoder.snapshot.date(for: candidates(for: key)), for: key)
    }

    func decodeIfPresent(_ type: Date.Type, forKey key: Key) throws -> Date? {
        decoder.snapshot.date(for: candidates(for: key))
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let names = candidates(for: key)
        if let numeric = decoder.snapshot.double(for: names) {
            return numeric != 0
        }
        if let string = decoder.snapshot.string(for: names) {
            return (string as NSString).boolValue
        }
        throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Missing value for \(key.stringValue)"))
    }

    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
        let names = candidates(for: key)
        if let numeric = decoder.snapshot.double(for: names) {
            return numeric != 0
        }
        if let string = decoder.snapshot.string(for: names) {
            return (string as NSString).boolValue
        }
        return nil
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        if T.self == String.self { return try decode(String.self, forKey: key) as! T }
        if T.self == Double.self { return try decode(Double.self, forKey: key) as! T }
        if T.self == Int.self { return try decode(Int.self, forKey: key) as! T }
        if T.self == Decimal.self { return try decode(Decimal.self, forKey: key) as! T }
        if T.self == Date.self { return try decode(Date.self, forKey: key) as! T }
        if T.self == Bool.self { return try decode(Bool.self, forKey: key) as! T }
        throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Unsupported type \(T.self)"))
    }

    func decodeIfPresent<T>(_ type: T.Type, forKey key: Key) throws -> T? where T: Decodable {
        guard let rawValue = lookup(for: key) else { return nil }
        guard case .some = rawValue else { return nil }
        return try decode(T.self, forKey: key)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        throw DecodingError.typeMismatch([String: Any].self, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Nested containers are not supported."))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Nested containers are not supported."))
    }

    func superDecoder() throws -> any Decoder {
        throw DecodingError.typeMismatch((any Decoder).self, DecodingError.Context(codingPath: codingPath, debugDescription: "Super decoders are not supported."))
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        throw DecodingError.typeMismatch((any Decoder).self, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Super decoders are not supported."))
    }
}

#if DEBUG
public func logParadoxDecodingError(_ error: any Error, record: String) {
    print("[ParadoxDecoder] Failed to decode \(record): \(error)")
}
#else
@inline(__always) public func logParadoxDecodingError(_ error: Error, record: String) {}
#endif
