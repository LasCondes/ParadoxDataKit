import Foundation

/// The rich value types that can be produced by Paradox table decoding.
public enum ParadoxValue: Equatable {
    case text(String)
    case integer(Int64)
    case double(Double)
    case decimal(Decimal)
    case bool(Bool)
    case date(Date)
    case time(TimeInterval)
    case timestamp(Date)
    case bytes(Data)
    case raw(Data)
    case image(Data)

    /// Returns a string representation of the value suitable for diagnostics or previews.
    public func formattedString(
        dateFormatter customDateFormatter: DateFormatter? = nil,
        timestampFormatter customTimestampFormatter: DateFormatter? = nil
    ) -> String {
        let dateFormatter = customDateFormatter ?? ParadoxValue.Formatters.date
        let timestampFormatter = customTimestampFormatter ?? ParadoxValue.Formatters.timestamp
        switch self {
        case .text(let string):
            return string
        case .integer(let value):
            return ParadoxValue.Formatters.number.string(from: NSNumber(value: value)) ?? String(value)
        case .double(let value):
            return ParadoxValue.Formatters.number.string(from: NSNumber(value: value)) ?? String(value)
        case .decimal(let value):
            let number = NSDecimalNumber(decimal: value)
            return ParadoxValue.Formatters.decimal.string(from: number) ?? number.stringValue
        case .bool(let flag):
            return flag ? "true" : "false"
        case .date(let date):
            return dateFormatter.string(from: date)
        case .time(let interval):
            return ParadoxValue.Formatters.timeString(interval: interval)
        case .timestamp(let date):
            return timestampFormatter.string(from: date)
        case .bytes(let data):
            return data.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .raw(let data):
            guard !data.isEmpty else { return "" }
            return data.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .image:
            return "[Image]"
        }
    }

    enum Formatters {
        static let number: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 6
            formatter.minimumFractionDigits = 0
            formatter.numberStyle = .decimal
            return formatter
        }()

        static let decimal: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 6
            formatter.numberStyle = .decimal
            return formatter
        }()

        static let date: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.calendar = Calendar(identifier: .gregorian)
            return formatter
        }()

        static let timestamp: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.calendar = Calendar(identifier: .gregorian)
            return formatter
        }()

        static func timeString(interval: TimeInterval) -> String {
            let totalSeconds = max(0, Int(interval.rounded()))
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }
}

/// Associates a decoded ``ParadoxValue`` with its originating ``ParadoxFieldDescriptor``.
public struct ParadoxFieldValue: Equatable {
    public let descriptor: ParadoxFieldDescriptor
    public let value: ParadoxValue?

    public init(descriptor: ParadoxFieldDescriptor, value: ParadoxValue?) {
        self.descriptor = descriptor
        self.value = value
    }
}

/// A single logical record (row) decoded from a Paradox table.
public struct ParadoxRecord: Equatable {
    public let raw: Data
    private let descriptors: [ParadoxFieldDescriptor]
    private let blobStore: ParadoxBlobStore?

    init(raw: Data, descriptors: [ParadoxFieldDescriptor], blobStore: ParadoxBlobStore?) {
        self.raw = raw
        self.descriptors = descriptors
        self.blobStore = blobStore
    }

    /// Returns the typed values for each field in the record.
    /// - Parameter encoding: The string encoding to use when decoding textual data.
    public func values(encoding: String.Encoding = .windowsCP1252) -> [ParadoxFieldValue] {
        var result: [ParadoxFieldValue] = []
        var cursor = 0

        for descriptor in descriptors {
            let length = descriptor.length
            guard length > 0 else {
                result.append(ParadoxFieldValue(descriptor: descriptor, value: .raw(Data())))
                continue
            }

            let remaining = raw.count - cursor
            guard remaining > 0 else {
                result.append(ParadoxFieldValue(descriptor: descriptor, value: nil))
                continue
            }

            let sliceLength = min(length, remaining)
            let fieldSlice = Data(raw[cursor..<(cursor + sliceLength)])
            cursor += sliceLength

            let value = Self.decodeValue(for: descriptor, bytes: fieldSlice, encoding: encoding, blobStore: blobStore)
            result.append(ParadoxFieldValue(descriptor: descriptor, value: value))
        }

        return result
    }

    /// Formats each field as a string for display or export.
    public func formattedValues(encoding: String.Encoding = .windowsCP1252) -> [String] {
        return values(encoding: encoding).map { field in
            if let value = field.value {
                return value.formattedString()
            }
            return "NULL"
        }
    }

    /// Looks up the value for a specific field name.
    /// - Parameters:
    ///   - name: Field name to search for (case-insensitive).
    ///   - encoding: String encoding for textual fields.
    public func value(named name: String, encoding: String.Encoding = .windowsCP1252) -> ParadoxValue? {
        let normalized = name.uppercased()
        for entry in values(encoding: encoding) {
            if entry.descriptor.name?.uppercased() == normalized {
                return entry.value
            }
        }
        return nil
    }

    private static func decodeValue(for descriptor: ParadoxFieldDescriptor, bytes: Data, encoding: String.Encoding, blobStore: ParadoxBlobStore?) -> ParadoxValue? {
        guard !bytes.isEmpty else {
            return nil
        }

        switch descriptor.typeCode {
        case 0x01: // Alpha
            return .text(Self.decodeAlpha(bytes: bytes, encoding: encoding))
        case 0x02: // Date
            return Self.decodeDate(bytes: bytes)
        case 0x03: // Short
            return Self.decodeShort(bytes: bytes)
        case 0x04: // Long
            return Self.decodeLong(bytes: bytes)
        case 0x05: // Currency
            return Self.decodeCurrency(bytes: bytes)
        case 0x06: // Number (double)
            if let double = Self.decodeDouble(bytes: bytes) {
                return .double(double)
            }
            return nil
        case 0x07, 0x09: // Logical
            if let value = Self.decodeLogical(bytes: bytes) {
                return .bool(value)
            }
            return nil
        case 0x08, 0x0C, 0x0E:
            if let string = blobStore?.resolveMemoField(bytes: bytes, encoding: encoding) {
                return .text(string)
            }
            return .raw(bytes)
        case 0x0D, 0x0F:
            if let data = blobStore?.resolveBinaryField(bytes: bytes) {
                return .bytes(data)
            }
            return .raw(bytes)
        case 0x10: // Graphic
            if let data = blobStore?.resolveBinaryField(bytes: bytes) {
                return .image(data)
            }
            return .image(bytes)
        case 0x18: // Bytes
            return .bytes(bytes)
        case 0x14: // Time
            return Self.decodeTime(bytes: bytes)
        case 0x15: // Timestamp
            return Self.decodeTimestamp(bytes: bytes)
        case 0x16: // Auto increment
            return Self.decodeLong(bytes: bytes)
        case 0x17: // BCD
            return Self.decodeBCD(bytes: bytes, scale: descriptor.length)
        default:
            if Self.isLikelyText(bytes: bytes) {
                return .text(Self.decodeAlpha(bytes: bytes, encoding: encoding))
            }
            return .raw(bytes)
        }
    }

    private static func decodeAlpha(bytes: Data, encoding: String.Encoding) -> String {
        var trimmed = bytes
        while let first = trimmed.first, first == 0x00 {
            trimmed.removeFirst()
        }
        while let last = trimmed.last, last == 0x00 || last == 0x20 {
            trimmed.removeLast()
        }
        if trimmed.isEmpty { return "" }
        let sanitized = Data(trimmed.map { $0 == 0 ? UInt8(0x20) : $0 })
        if let string = String(data: sanitized, encoding: encoding) { return string }
        if let latin1 = String(data: sanitized, encoding: .isoLatin1) { return latin1 }
        if let ascii = String(data: sanitized, encoding: .ascii) { return ascii }
        let replacement = UnicodeScalar(0xFFFD)!
        let fallbackScalars: [UnicodeScalar] = trimmed.map { byte in
            if byte >= 0x20 && byte <= 0x7E {
                return UnicodeScalar(byte)
            }
            return replacement
        }
        return String(String.UnicodeScalarView(fallbackScalars))
    }

    private static func decodeShort(bytes: Data) -> ParadoxValue? {
        guard bytes.count >= 2 else { return nil }
        var tmp = [UInt8](bytes.prefix(2))
        if tmp[0] & 0x80 != 0 {
            tmp[0] &= 0x7F
        } else if tmp.contains(where: { $0 != 0 }) {
            tmp[0] |= 0x80
        } else {
            return .integer(0)
        }
        let value = Self.bigEndianSignedValue(tmp)
        return .integer(Int64(value))
    }

    private static func decodeLong(bytes: Data) -> ParadoxValue? {
        guard bytes.count >= 4 else { return nil }
        var tmp = [UInt8](bytes.prefix(4))
        if tmp[0] & 0x80 != 0 {
            tmp[0] &= 0x7F
        } else if tmp.contains(where: { $0 != 0 }) {
            tmp[0] |= 0x80
        } else {
            return .integer(0)
        }
        let value = Self.bigEndianSignedValue(tmp)
        return .integer(Int64(value))
    }

    private static func decodeCurrency(bytes: Data) -> ParadoxValue? {
        guard let double = decodeDouble(bytes: bytes) else { return nil }
        return .double(double)
    }

    private static func decodeDouble(bytes: Data) -> Double? {
        guard bytes.count >= 8 else { return nil }
        var tmp = [UInt8](bytes.prefix(8))
        if tmp[0] & 0x80 != 0 {
            tmp[0] &= 0x7F
        } else if tmp.contains(where: { $0 != 0 }) {
            for index in tmp.indices {
                tmp[index] = ~tmp[index]
            }
        } else {
            return 0
        }
        var bitPattern: UInt64 = 0
        for byte in tmp {
            bitPattern = (bitPattern << 8) | UInt64(byte)
        }
        return Double(bitPattern: bitPattern)
    }

    private static func decodeLogical(bytes: Data) -> Bool? {
        guard let first = bytes.first else { return nil }
        if first == 0 { return nil }
        if first & 0x80 != 0 {
            return (first & 0x7F) != 0
        }
        return ((first | 0x80) & 0x7F) != 0
    }

    private static func decodeDate(bytes: Data) -> ParadoxValue? {
        guard bytes.count >= 4 else { return nil }
        var tmp = [UInt8](bytes.prefix(4))
        if tmp[0] & 0x80 != 0 {
            tmp[0] &= 0x7F
        } else if tmp.contains(where: { $0 != 0 }) {
            tmp[0] |= 0x80
        } else {
            return nil
        }
        let days = Int(bigEndianSignedValue(tmp))
        guard days > 0, let base = Self.baseDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(byAdding: .day, value: days - 1, to: base)
        if let date {
            return .date(date)
        }
        return nil
    }

    private static func decodeTime(bytes: Data) -> ParadoxValue? {
        guard bytes.count >= 4 else { return nil }
        var tmp = [UInt8](bytes.prefix(4))
        if tmp[0] & 0x80 != 0 {
            tmp[0] &= 0x7F
        } else if tmp.contains(where: { $0 != 0 }) {
            tmp[0] |= 0x80
        } else {
            return nil
        }
        let ticks = UInt32(bigEndianUnsignedValue(tmp))
        let seconds = TimeInterval(ticks) / 1000.0
        return .time(seconds)
    }

    private static func decodeTimestamp(bytes: Data) -> ParadoxValue? {
        guard let doubleValue = decodeDouble(bytes: bytes) else { return nil }
        guard let base = Self.baseDate else { return nil }
        let integral = floor(doubleValue)
        let fractional = doubleValue - integral
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(byAdding: .day, value: Int(integral) - 1, to: base) else { return nil }
        let seconds = fractional * 86_400.0
        let final = date.addingTimeInterval(seconds)
        return .timestamp(final)
    }

    private static func decodeBCD(bytes: Data, scale: Int) -> ParadoxValue? {
        guard let first = bytes.first, first != 0, bytes.count >= 17 else {
            return nil
        }
        let indicatedScale = Int(first & 0x3F)
        let effectiveScale = scale > 0 ? scale : indicatedScale
        let isPositive = (first & 0x80) != 0
        let signMask: UInt8 = isPositive ? 0x00 : 0x0F
        let array = [UInt8](bytes.prefix(17))

        func nibble(at index: Int) -> UInt8 {
            let byteIndex = index / 2
            let nibble: UInt8
            if index % 2 == 0 {
                nibble = (array[byteIndex] >> 4) & 0x0F
            } else {
                nibble = array[byteIndex] & 0x0F
            }
            return nibble ^ signMask
        }

        var integerDigits: [Character] = []
        var leadingZero = true
        var nibbleIndex = 2
        let integerLimit = 34 - effectiveScale
        while nibbleIndex < integerLimit {
            let digit = nibble(at: nibbleIndex)
            if leadingZero {
                if digit != 0 {
                    leadingZero = false
                    if let scalar = UnicodeScalar(Int(digit) + 48) {
                        integerDigits.append(Character(scalar))
                    }
                }
            } else {
                if let scalar = UnicodeScalar(Int(digit) + 48) {
                    integerDigits.append(Character(scalar))
                }
            }
            nibbleIndex += 1
        }
        if integerDigits.isEmpty { integerDigits.append("0") }

        var fraction = ""
        while nibbleIndex < 34 {
            let digit = nibble(at: nibbleIndex)
            fraction.append(String(digit))
            nibbleIndex += 1
        }
        if fraction.count > effectiveScale {
            fraction = String(fraction.prefix(effectiveScale))
        } else if fraction.count < effectiveScale {
            fraction = fraction.padding(toLength: effectiveScale, withPad: "0", startingAt: 0)
        }

        var numberString = String(integerDigits)
        if effectiveScale > 0 {
            numberString.append(".")
            numberString.append(fraction)
        }
        if !isPositive {
            numberString = "-" + numberString
        }

        return Decimal(string: numberString, locale: Locale(identifier: "en_US_POSIX")).map { .decimal($0) }
    }

    private static func bigEndianSignedValue(_ bytes: [UInt8]) -> Int64 {
        var value: Int64 = 0
        for byte in bytes {
            value = (value << 8) | Int64(byte)
        }
        let bits = bytes.count * 8
        let shift = 64 - bits
        return (value << shift) >> shift
    }

    private static func bigEndianUnsignedValue(_ bytes: [UInt8]) -> UInt64 {
        var value: UInt64 = 0
        for byte in bytes {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }

    private static let baseDate: Date? = {
        var components = DateComponents()
        components.year = 1
        components.month = 1
        components.day = 1
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return components.date
    }()

    private static func isLikelyText(bytes: Data) -> Bool {
        guard !bytes.isEmpty else { return true }
        var printable = 0
        for byte in bytes {
            if byte == 0 { continue }
            if byte >= 0x20 && byte <= 0x7E { printable += 1; continue }
            if byte >= 0x80 { printable += 1; continue }
            return false
        }
        return printable > 0
    }
}

public extension ParadoxRecord {
    static func == (lhs: ParadoxRecord, rhs: ParadoxRecord) -> Bool {
        lhs.raw == rhs.raw && lhs.descriptors == rhs.descriptors
    }
}
