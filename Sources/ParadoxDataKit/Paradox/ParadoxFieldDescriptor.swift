import Foundation

/// Metadata describing a field within a Paradox table.
public struct ParadoxFieldDescriptor: Equatable, Hashable {
    public let index: Int
    public let length: Int
    public let typeCode: UInt8
    public let name: String?

    public init(index: Int, length: Int, typeCode: UInt8, name: String?) {
        self.index = index
        self.length = length
        self.typeCode = typeCode
        self.name = name
    }

    /// Human-readable label for the Paradox field type.
    public var typeDescription: String {
        ParadoxFieldDescriptor.describe(typeCode: typeCode)
    }

    static func describe(typeCode: UInt8) -> String {
        switch typeCode {
        case 0x01: return "Alpha"
        case 0x02: return "Date"
        case 0x03: return "Short"
        case 0x04: return "Long"
        case 0x05: return "Currency"
        case 0x06: return "Number"
        case 0x07: return "Logical"
        case 0x08: return "Memo"
        case 0x09: return "Logical"
        case 0x0C: return "Memo BLOB"
        case 0x0D: return "Binary BLOB"
        case 0x0E: return "Formatted Memo"
        case 0x0F: return "OLE"
        case 0x10: return "Graphic"
        case 0x14: return "Time"
        case 0x15: return "Timestamp"
        case 0x16: return "Auto increment"
        case 0x17: return "BCD"
        case 0x18: return "Bytes"
        default:
            return "Unknown(0x\(String(format: "%02X", typeCode)))"
        }
    }
}
