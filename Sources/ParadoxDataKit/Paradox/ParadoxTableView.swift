import Foundation

/// Parsed metadata for a Paradox table view (``.tv``) file.
public struct ParadoxTableView {
    public let signature: String
    public let version: UInt16?
    public let flags: UInt16?
    public let declaredLength: UInt32?
    public let firstBlockOffset: UInt16?
    public let directoryHint: String?
    public let tableFileName: String?
    public let additionalStrings: [String]
    public let binary: GenericBinaryFile

    public init(data: Data) throws {
        guard data.count >= 32 else {
            throw ParadoxTableViewError.fileTooSmall
        }

        let signatureText = "Borland Standard File"
        let signatureBytes = Array(signatureText.utf8)
        guard data.starts(with: signatureBytes) else {
            throw ParadoxTableViewError.invalidSignature
        }

        self.signature = signatureText
        self.binary = GenericBinaryFile(data: data)

        var cursor = signatureBytes.count

        cursor = Self.skipZeros(in: data, startingAt: cursor)

        self.version = Self.readUInt16(from: data, cursor: &cursor)
        self.flags = Self.readUInt16(from: data, cursor: &cursor)
        self.declaredLength = Self.readUInt32(from: data, cursor: &cursor)
        self.firstBlockOffset = Self.readUInt16(from: data, cursor: &cursor)

        cursor = Self.skipZeros(in: data, startingAt: cursor)

        let (directory, afterDirectory) = Self.readCString(in: data, startingAt: cursor)
        self.directoryHint = directory
        cursor = afterDirectory

        let (tableName, afterTable) = Self.readCString(in: data, startingAt: cursor)
        self.tableFileName = tableName
        cursor = afterTable

        var remainingStrings: [String] = []
        var attemptCursor = cursor
        let maximumStringCount = 4
        while remainingStrings.count < maximumStringCount && attemptCursor < data.count {
            let (value, next) = Self.readCString(in: data, startingAt: attemptCursor)
            attemptCursor = next
            guard let value = value else { break }
            guard !value.isEmpty else { continue }
            remainingStrings.append(value)
        }
        self.additionalStrings = remainingStrings
    }

    public var resolvedTableReference: String? {
        if let directoryHint, let tableFileName {
            if directoryHint.hasSuffix("\\") || directoryHint.hasSuffix("/") {
                return directoryHint + tableFileName
            }
            return directoryHint + "\\" + tableFileName
        }
        return tableFileName ?? directoryHint
    }

    public enum ParadoxTableViewError: Error, LocalizedError {
        case fileTooSmall
        case invalidSignature

        public var errorDescription: String? {
            switch self {
            case .fileTooSmall:
                return "The table view file is too small to contain a valid header."
            case .invalidSignature:
                return "The file does not begin with the expected Borland Standard File signature."
            }
        }
    }

    private static func skipZeros(in data: Data, startingAt index: Int) -> Int {
        var cursor = index
        while cursor < data.count, data[cursor] == 0 {
            cursor = data.index(after: cursor)
        }
        return cursor
    }

    private static func readUInt16(from data: Data, cursor: inout Int) -> UInt16? {
        guard cursor + 2 <= data.count else { return nil }
        let value = data[cursor..<(cursor + 2)].withUnsafeBytes { $0.load(as: UInt16.self) }
        cursor += 2
        return UInt16(littleEndian: value)
    }

    private static func readUInt32(from data: Data, cursor: inout Int) -> UInt32? {
        guard cursor + 4 <= data.count else { return nil }
        let value = data[cursor..<(cursor + 4)].withUnsafeBytes { $0.load(as: UInt32.self) }
        cursor += 4
        return UInt32(littleEndian: value)
    }

    private static func readCString(in data: Data, startingAt index: Int) -> (String?, Int) {
        guard index < data.count else { return (nil, data.count) }
        var end = index
        while end < data.count, data[end] != 0 {
            end = data.index(after: end)
        }

        let bytes = data[index..<end]
        let string = String(data: bytes, encoding: .windowsCP1252) ?? String(data: bytes, encoding: .ascii)

        var cursor = end
        while cursor < data.count, data[cursor] == 0 {
            cursor = data.index(after: cursor)
        }

        return (string, cursor)
    }
}
