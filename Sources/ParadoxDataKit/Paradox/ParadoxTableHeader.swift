import Foundation

/// Raw metadata describing a Paradox table header.
public struct ParadoxTableHeader {
    public let raw: Data

    public init(raw: Data) {
        self.raw = raw
    }

    public var recordSize: UInt16 {
        readWord(at: 0)
    }

    public var headerLengthInBytes: Int {
        Int(readWord(at: 0x02))
    }

    public var realHeaderSize: Int {
        Int(readWord(at: 0x51))
    }

    /// Enumerates known Paradox file types encoded in the header.
    public enum FileType: UInt8, CaseIterable {
        case indexDB = 0x00
        case primaryIndex = 0x01
        case nonIndexDB = 0x02
        case nonIncrementalSecondaryIndex = 0x03
        case secondaryIndex = 0x04
        case incrementalSecondaryIndex = 0x05
        case nonIncrementalSecondaryIndexGraph = 0x06
        case secondaryIndexGraph = 0x07
        case incrementalSecondaryIndexGraph = 0x08

        /// A readable description of the file type.
        public var summary: String {
            switch self {
            case .indexDB: return "Indexed table (.DB + .PX)"
            case .primaryIndex: return "Primary index (.PX)"
            case .nonIndexDB: return "Unindexed table (.DB)"
            case .nonIncrementalSecondaryIndex: return "Non-incremental secondary index (.Xnn)"
            case .secondaryIndex: return "Secondary index (.Ynn)"
            case .incrementalSecondaryIndex: return "Incremental secondary index (.Xnn)"
            case .nonIncrementalSecondaryIndexGraph: return "Graph secondary index (.XGn)"
            case .secondaryIndexGraph: return "Graph index (.YGn)"
            case .incrementalSecondaryIndexGraph: return "Incremental graph index (.XGn)"
            }
        }
    }

    public var fileTypeRaw: UInt8 {
        guard raw.count > 0x04 else { return 0 }
        return raw[0x04]
    }

    public var fileType: FileType? {
        FileType(rawValue: fileTypeRaw)
    }

    public var maxTableSizeFactor: UInt8 {
        guard raw.count > 0x05 else { return 0 }
        return raw[0x05]
    }

    public var fileVersionID: UInt8 {
        guard raw.count > 0x39 else { return 0 }
        return raw[0x39]
    }

    public var normalizedFileVersion: Int {
        switch fileVersionID {
        case 0x03: return 30
        case 0x04: return 35
        case 0x05, 0x06, 0x07, 0x08, 0x09: return 40
        case 0x0A, 0x0B: return 50
        case 0x0C: return 70
        default: return 0
        }
    }

    public var rowCount: UInt32 {
        readDoubleWord(at: 0x06)
    }

    public var fieldCount: UInt16 {
        readWord(at: 0x21)
    }

    public var keyFieldCount: UInt16 {
        readWord(at: 0x23)
    }

    public var autoIncrementValue: UInt32 {
        readDoubleWord(at: 0x48)
    }

    public var includesDataHeader: Bool {
        switch fileTypeRaw {
        case 0x00, 0x02, 0x03, 0x05:
            return normalizedFileVersion >= 40
        default:
            return false
        }
    }

    public var fieldInfoOffset: Int {
        includesDataHeader ? 0x78 : 0x58
    }

    public var dataBlockSize: Int {
        let factor = Int(maxTableSizeFactor)
        return factor > 0 ? factor * 0x400 : 0x400
    }

    public var description: String {
        "recordSize=\(recordSize) bytes, fields=\(fieldCount), rows=\(rowCount)"
    }

    private func readWord(at index: Int) -> UInt16 {
        BinaryDataReader.readUInt16(from: raw, at: index) ?? 0
    }

    private func readDoubleWord(at index: Int) -> UInt32 {
        BinaryDataReader.readUInt32(from: raw, at: index) ?? 0
    }
}
