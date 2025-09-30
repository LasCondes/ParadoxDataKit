import Foundation

public struct FieldSnapshot {
    public typealias NormalizedName = String

    private let entries: [(name: NormalizedName, value: ParadoxValue?)]
    private let map: [NormalizedName: ParadoxValue?]

    public init(record: ParadoxRecord) {
        var collected: [(NormalizedName, ParadoxValue?)] = []
        collected.reserveCapacity(record.values().count)

        for field in record.values() {
            guard let rawName = field.descriptor.name, !rawName.isEmpty else { continue }
            let normalized = FieldSnapshot.normalize(rawName)
            collected.append((normalized, field.value))
        }

        self.entries = collected
        var lookup: [NormalizedName: ParadoxValue?] = [:]
        for (name, value) in collected where lookup[name] == nil {
            lookup[name] = value
        }
        self.map = lookup
    }

    public func string(for keys: [NormalizedName]) -> String? {
        for key in keys {
            if let candidate = map[key], let string = FieldSnapshot.string(from: candidate) {
                return string
            }
        }
        return nil
    }

    public func double(for keys: [NormalizedName]) -> Double? {
        for key in keys {
            if let candidate = map[key], let numeric = FieldSnapshot.double(from: candidate) {
                return numeric
            }
        }
        return nil
    }

    public func int(for keys: [NormalizedName]) -> Int? {
        for key in keys {
            if let candidate = map[key], let numeric = FieldSnapshot.int(from: candidate) {
                return numeric
            }
        }
        return nil
    }

    public func date(for keys: [NormalizedName]) -> Date? {
        for key in keys {
            if let candidate = map[key], let date = FieldSnapshot.date(from: candidate) {
                return date
            }
        }
        return nil
    }

    public func identifier(for keys: [NormalizedName]) -> String? {
        for key in keys {
            if let candidate = map[key], let string = FieldSnapshot.identifierString(from: candidate) {
                return string
            }
        }
        return nil
    }

    public func identifierFromNumericID(for keys: [NormalizedName]) -> String? {
        for key in keys {
            if let candidate = map[key], let numeric = FieldSnapshot.double(from: candidate) {
                return FieldSnapshot.format(identifier: numeric)
            }
        }
        return nil
    }

    public func decimal(for keys: [NormalizedName]) -> Decimal? {
        for key in keys {
            if let candidate = map[key], let decimal = FieldSnapshot.decimal(from: candidate) {
                return decimal
            }
        }
        return nil
    }

    public func addressLines() -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(4)
        let skipPrefixes: Set<NormalizedName> = [
            "CITY",
            "STATE",
            "POSTALCODE",
            "ZIP",
            "ZIPCODE",
            "POSTCODE",
            "COUNTRY",
            "REGION",
            "PROVINCE"
        ]

        for (name, value) in entries {
            guard !skipPrefixes.contains(name) else { continue }
            guard let string = FieldSnapshot.string(from: value), !string.isEmpty else { continue }
            if !lines.contains(string) {
                lines.append(string)
            }
        }

        return lines
    }

    public func value(forNormalizedName name: NormalizedName) -> ParadoxValue?? {
        map[name]
    }

    public func contains(_ name: NormalizedName) -> Bool {
        map.keys.contains(name)
    }

    public var normalizedNames: [NormalizedName] {
        Array(map.keys)
    }

    public static func normalizeKey(_ raw: String) -> NormalizedName {
        normalize(raw)
    }

    public static func format(identifier value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return String(value)
        }
        if abs(value.rounded() - value) < 0.000_000_1 {
            return String(Int(value.rounded()))
        }
        return String(value)
    }

    public static func trimmedOrNil(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func trimmedOrNil(_ string: String?) -> String? {
        guard let string else { return nil }
        return trimmedOrNil(string)
    }

    private static func normalize(_ raw: String) -> NormalizedName {
        let uppercased = raw.uppercased()
        let filtered = uppercased.filter { $0.isLetter || $0.isNumber }
        return filtered
    }

    private static func string(from value: ParadoxValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .text(let string):
            return trimmedOrNil(string)
        case .integer(let integer):
            return String(integer)
        case .double(let double):
            return format(identifier: double)
        case .decimal(let decimal):
            return NSDecimalNumber(decimal: decimal).stringValue.letTrimmed()
        case .date(let date):
            return FieldSnapshot.dateFormatter.string(from: date)
        case .timestamp(let date):
            return FieldSnapshot.timestampFormatter.string(from: date)
        default:
            return nil
        }
    }

    private static func identifierString(from value: ParadoxValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .text(let string):
            return trimmedOrNil(string)
        case .integer(let integer):
            return String(integer)
        case .double(let double):
            return format(identifier: double)
        case .decimal(let decimal):
            return NSDecimalNumber(decimal: decimal).stringValue.letTrimmed()
        default:
            return nil
        }
    }

    private static func double(from value: ParadoxValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .double(let double):
            return double
        case .integer(let integer):
            return Double(integer)
        case .decimal(let decimal):
            return NSDecimalNumber(decimal: decimal).doubleValue
        case .text(let string):
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func int(from value: ParadoxValue?) -> Int? {
        if let double = double(from: value) {
            return Int(double.rounded())
        }
        return nil
    }

    private static func decimal(from value: ParadoxValue?) -> Decimal? {
        guard let value else { return nil }
        switch value {
        case .decimal(let decimal):
            return decimal
        case .double(let double):
            return Decimal(double)
        case .integer(let integer):
            return Decimal(integer)
        case .text(let string):
            return Decimal(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func date(from value: ParadoxValue?) -> Date? {
        guard let value else { return nil }
        switch value {
        case .date(let date):
            return date
        case .timestamp(let date):
            return date
        case .text(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = dateFormatter.date(from: trimmed) {
                return date
            }
            if let date = timestampFormatter.date(from: trimmed) {
                return date
            }
            return nil
        default:
            return nil
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

private extension String {
    func letTrimmed() -> String? {
        FieldSnapshot.trimmedOrNil(self)
    }
}
