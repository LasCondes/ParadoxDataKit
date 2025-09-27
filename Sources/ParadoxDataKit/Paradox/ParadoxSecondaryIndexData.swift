import Foundation

/// Parsed representation of a Paradox secondary index data table (`.Xnn`).
public struct ParadoxSecondaryIndexData {
    public let table: ParadoxTable
    public let secondaryFieldReferences: [UInt16]
    public let sortOrder: String?
    public let indexLabel: String?

    /// Names of the key fields in order (secondary key fields first, followed by primary key fields).
    public var keyFieldNames: [String] {
        Array(table.fieldNames.prefix(Int(table.header.keyFieldCount)))
    }

    /// Name of the hint field, if present.
    public var hintFieldName: String? {
        table.fieldNames.last
    }

    public init(data: Data) throws {
        let table = try ParadoxTable(data: data)
        self.table = table

        let headerArea = table.headerArea
        let header = table.header
        let fieldCount = Int(header.fieldCount)

        // Recreate the parsing offsets used when decoding the base table header.
        let descriptorOffset = header.fieldInfoOffset
        let descriptorBytesNeeded = fieldCount * 2
        let pointerSectionLength = 4 + fieldCount * 4
        let fieldNumberSectionLength = fieldCount * 2
        var cursor = descriptorOffset + descriptorBytesNeeded + pointerSectionLength + fieldNumberSectionLength

        // Skip table name and field names (they already exist on `table`).
        // There are `fieldCount + 1` strings: table name + field names.
        for _ in 0...fieldCount { // inclusive to skip table name
            guard cursor < headerArea.count else { break }
            while cursor < headerArea.count, headerArea[cursor] != 0 {
                cursor += 1
            }
            while cursor < headerArea.count, headerArea[cursor] == 0 {
                cursor += 1
            }
        }

        var references: [UInt16] = []
        references.reserveCapacity(fieldCount)
        var refsCursor = cursor
        for _ in 0..<fieldCount {
            guard refsCursor + 2 <= headerArea.count else { break }
            let value = BinaryDataReader.readUInt16(from: headerArea, at: refsCursor) ?? 0
            references.append(value)
            refsCursor += 2
        }
        cursor = refsCursor
        self.secondaryFieldReferences = references

        // Sort order string (null terminated)
        if cursor < headerArea.count {
            let sort = ParadoxSecondaryIndexData.readCString(from: headerArea, startingAt: &cursor)
            self.sortOrder = sort.isEmpty ? nil : sort
        } else {
            self.sortOrder = nil
        }

        if cursor < headerArea.count {
            let label = ParadoxSecondaryIndexData.readCString(from: headerArea, startingAt: &cursor)
            self.indexLabel = label.isEmpty ? nil : label
        } else {
            self.indexLabel = nil
        }
    }

    private static func readCString(from data: Data, startingAt cursor: inout Int) -> String {
        guard cursor < data.count else { return "" }
        let start = cursor
        while cursor < data.count, data[cursor] != 0 {
            cursor += 1
        }
        let slice = data[start..<cursor]
        if cursor < data.count { cursor += 1 }
        let string = String(bytes: slice, encoding: .windowsCP1252) ?? String(bytes: slice, encoding: .ascii) ?? ""
        while cursor < data.count, data[cursor] == 0 {
            cursor += 1
        }
        return string
    }
}
