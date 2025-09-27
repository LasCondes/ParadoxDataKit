import Foundation

/// A fully parsed Borland Paradox table (``.db``) including header metadata,
/// field definitions, and decoded record values.
public struct ParadoxTable {
    public let header: ParadoxTableHeader
    public let fields: [ParadoxFieldDescriptor]
    public let records: [ParadoxRecord]
    public let headerArea: Data
    public let recordArea: Data
    public let fieldNames: [String]

    public let tableName: String?
    public let sortOrder: String?
    public let codePageIdentifier: UInt16?
    public let autoIncrementSeed: Int64?

    /// Creates a `ParadoxTable` from raw Paradox table data.
    /// - Parameters:
    ///   - data: The complete contents of a Paradox table file.
    ///   - fileURL: Optional URL of the source file, used to locate memo/graphic blobs.
    public init(data: Data, fileURL: URL? = nil) throws {
        guard data.count >= 128 else {
            throw ParadoxTableError.fileTooSmall
        }

        let baseHeaderLength = 128
        let baseHeader = Data(data.prefix(baseHeaderLength))
        let parsedHeader = ParadoxTableHeader(raw: baseHeader)
        let minimumHeaderBytes = max(parsedHeader.fieldInfoOffset, baseHeaderLength)
        let headerLength: Int = {
            let declared = parsedHeader.headerLengthInBytes
            if declared == 0 {
                return minimumHeaderBytes
            }
            return min(max(declared, minimumHeaderBytes), data.count)
        }()

        let headerArea = Data(data.prefix(headerLength))
        let recordArea = Data(data.dropFirst(headerLength))
        let fieldCount = Int(parsedHeader.fieldCount)

        let descriptorOffset = parsedHeader.fieldInfoOffset
        let descriptorBytesNeeded = fieldCount * 2
        guard descriptorOffset + descriptorBytesNeeded <= headerArea.count else {
            throw ParadoxTableError.missingFieldDescriptors
        }

        let descriptorSlice = headerArea[descriptorOffset..<(descriptorOffset + descriptorBytesNeeded)]

        let pointerSectionLength = 4 + fieldCount * 4
        let fieldNumberSectionLength = fieldCount * 2

        let namesStart = descriptorOffset + descriptorBytesNeeded + pointerSectionLength + fieldNumberSectionLength
        let namesRegion = namesStart < headerArea.count ? headerArea.suffix(from: namesStart) : Data()
        let (extractedTableName, parsedFieldNames, remainingAfterNames) = ParadoxTable.parseNames(from: namesRegion, expectedCount: fieldCount)

        let blobStore = fileURL.flatMap { ParadoxBlobStore(tableURL: $0, declaredTableName: extractedTableName) }

        var descriptors: [ParadoxFieldDescriptor] = []
        descriptors.reserveCapacity(fieldCount)

        for index in 0..<fieldCount {
            let byteIndex = descriptorSlice.index(descriptorSlice.startIndex, offsetBy: index * 2)
            let type = descriptorSlice[byteIndex]
            let length = Int(descriptorSlice[descriptorSlice.index(after: byteIndex)])
            let name = index < parsedFieldNames.count ? parsedFieldNames[index] : nil
            descriptors.append(ParadoxFieldDescriptor(index: index, length: length, typeCode: type, name: name))
        }

        let recordSize = Int(parsedHeader.recordSize)
        guard recordSize > 0 else {
            throw ParadoxTableError.invalidRecordSize
        }

        let expectedRowCount = parsedHeader.rowCount == 0 ? nil : Int(parsedHeader.rowCount)
        var parsedRecords: [ParadoxRecord] = []
        parsedRecords.reserveCapacity(expectedRowCount ?? 0)

        let blockHeaderSize = 6
        let blockSize = max(parsedHeader.dataBlockSize, blockHeaderSize)
        var blockOffset = 0

        blockIteration: while blockOffset < recordArea.count {
            let remaining = recordArea.count - blockOffset
            guard remaining >= blockHeaderSize else { break }

            let currentBlockSize = min(blockSize, remaining)
            let dataStart = blockOffset + blockHeaderSize
            let dataEnd = min(blockOffset + currentBlockSize, recordArea.count)
            var cursor = dataStart

            while cursor + recordSize <= dataEnd {
                let slice = recordArea[cursor..<(cursor + recordSize)]
                cursor += recordSize
                if slice.allSatisfy({ $0 == 0 }) {
                    continue
                }
                parsedRecords.append(ParadoxRecord(raw: Data(slice), descriptors: descriptors, blobStore: blobStore))
                if let expectedRowCount, parsedRecords.count >= expectedRowCount {
                    break blockIteration
                }
            }

            blockOffset += currentBlockSize
        }

        self.header = parsedHeader
        self.fields = descriptors
        self.records = parsedRecords
        self.headerArea = headerArea
        self.recordArea = recordArea
        self.fieldNames = parsedFieldNames
        self.tableName = extractedTableName?.isEmpty == true ? nil : extractedTableName
        self.sortOrder = ParadoxTable.extractNullTerminatedString(from: remainingAfterNames)
        self.codePageIdentifier = BinaryDataReader.readUInt16(from: headerArea, at: 0x006A)
        if let value = BinaryDataReader.readUInt32(from: headerArea, at: 0x0049), value != 0 {
            self.autoIncrementSeed = Int64(value)
        } else {
            self.autoIncrementSeed = nil
        }
    }

    /// A human-readable summary of the table for quick diagnostics.
    public var summary: String {
        let namePart = tableName.map { "\($0) " } ?? ""
        return "Paradox table \(namePart)with \(fields.count) fields and \(records.count) loaded records"
    }

    /// Returns the display names for each field, falling back to generated names when necessary.
    public func fieldDisplayNames() -> [String] {
        fields.enumerated().map { index, descriptor in
            let sourceName = index < fieldNames.count ? fieldNames[index] : descriptor.name
            let trimmed = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed! : "Field \(index + 1)"
        }
    }

    /// Produces sample record rows formatted as strings for inspection or previews.
    /// - Parameters:
    ///   - sampleCount: Maximum number of rows to include.
    ///   - encoding: The string encoding used to decode character data.
    public func formattedRecords(sampleCount: Int = 32, encoding: String.Encoding = .windowsCP1252) -> [[String]] {
        records.prefix(sampleCount).map { $0.formattedValues(encoding: encoding) }
    }

    private static func parseNames(from data: Data, expectedCount: Int) -> (tableName: String?, fieldNames: [String], remaining: Data) {
        if data.isEmpty {
            return (nil, [], Data())
        }

        var iterator = data.startIndex
        let tableNameBytes = data.prefix { $0 != 0 }
        let tableName = String(bytes: tableNameBytes, encoding: .windowsCP1252) ?? String(bytes: tableNameBytes, encoding: .ascii)

        // advance iterator to the end of the table name padding
        iterator = data.index(data.startIndex, offsetBy: tableNameBytes.count)
        while iterator < data.endIndex && data[iterator] == 0 {
            iterator = data.index(after: iterator)
        }

        let namesData = data.suffix(from: iterator)
        let (names, remaining) = extractNames(from: namesData, expectedCount: expectedCount)
        return (tableName, names, remaining)
    }

    private static func extractNames(from data: Data, expectedCount: Int) -> ([String], Data) {
        guard expectedCount > 0 else { return ([], Data()) }
        var names: [String] = []
        var current: [UInt8] = []
        var index = data.startIndex
        names.reserveCapacity(expectedCount)

        while index < data.endIndex {
            let byte = data[index]
            if byte == 0 {
                let name = String(bytes: current, encoding: .windowsCP1252) ?? String(bytes: current, encoding: .ascii) ?? ""
                names.append(name)
                current.removeAll(keepingCapacity: true)
                index = data.index(after: index)
                if names.count == expectedCount {
                    let remaining = data.suffix(from: index)
                    return (names, remaining)
                }
                continue
            }
            current.append(byte)
            index = data.index(after: index)
        }

        if !current.isEmpty && names.count < expectedCount {
            let name = String(bytes: current, encoding: .windowsCP1252) ?? String(bytes: current, encoding: .ascii) ?? ""
            names.append(name)
        }

        return (names, Data())
    }

    private static func extractNullTerminatedString(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let prefix = data.prefix { $0 != 0 }
        guard !prefix.isEmpty else { return nil }
        return String(bytes: prefix, encoding: .windowsCP1252) ?? String(bytes: prefix, encoding: .ascii)
    }
}

/// Errors that may occur while parsing a Paradox table file.
public enum ParadoxTableError: Error, LocalizedError {
    case fileTooSmall
    case missingFieldDescriptors
    case invalidRecordSize

    public var errorDescription: String? {
        switch self {
        case .fileTooSmall:
            return "File is too small to contain a Paradox table header."
        case .missingFieldDescriptors:
            return "Incomplete field descriptor table."
        case .invalidRecordSize:
            return "The header reports an invalid record size."
        }
    }
}
