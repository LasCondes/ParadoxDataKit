import XCTest
@testable import ParadoxDataKit

final class ParadoxFileReaderTests: XCTestCase {
    func testParadoxTableParsesHeaderAndRecords() throws {
        let data = makeMockTable()
        let table = try ParadoxTable(data: data)

        XCTAssertEqual(table.fields.count, 2)
        XCTAssertEqual(table.fields[0].name, "CODE")
        XCTAssertEqual(table.fields[1].length, 6)
        XCTAssertEqual(table.records.count, 2)
        XCTAssertEqual(table.tableName, "MOCK.DB")
        XCTAssertEqual(table.fieldNames, ["CODE", "DESC"])

        let firstValues = table.records[0].values()
        XCTAssertEqual(firstValues[0].value, .text("A001"))
        XCTAssertEqual(firstValues[1].value, .text("Widget"))
    }

    func testReaderLoadsQuery() throws {
        let queryText = "SELECT * FROM CUSTOMER;"
        let data = Data(queryText.utf8)
        let file = try ParadoxFileReader.load(data: data, suggestedFormat: .paradoxQuery)

        guard case .paradoxQuery(let query) = file.details else {
            return XCTFail("Expected query details")
        }
        XCTAssertEqual(query.text, queryText)
    }

    func testUnsupportedFormatsFallbackToBinary() throws {
        let bytes = Data([0x00, 0x01, 0x02, 0x03])
        let file = try ParadoxFileReader.load(data: bytes, suggestedFormat: .paradoxReport)

        guard case .binary(let binary) = file.details else {
            return XCTFail("Expected binary details")
        }
        XCTAssertEqual(binary.size, 4)
        XCTAssertEqual(binary.headerPreview, bytes)
    }

    func testParadoxTableViewParsesMetadata() throws {
        var data = Data("Borland Standard File".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x0020).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1024).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x00A0).littleEndian, Array.init))
        data.append(contentsOf: "WORK:DATA\\CUS".utf8)
        data.append(0)
        data.append(contentsOf: "SAMPLE.DB".utf8)
        data.append(0)
        data.append(contentsOf: "Form Title".utf8)
        data.append(0)

        let file = try ParadoxFileReader.load(data: data, suggestedFormat: .paradoxForm)

        guard case .paradoxTableView(let view) = file.details else {
            return XCTFail("Expected table view details")
        }

        XCTAssertEqual(view.signature, "Borland Standard File")
        XCTAssertEqual(view.version, 1)
        XCTAssertEqual(view.flags, 0x0020)
        XCTAssertEqual(view.declaredLength, 1024)
        XCTAssertEqual(view.firstBlockOffset, 0x00A0)
        XCTAssertEqual(view.directoryHint, "WORK:DATA\\CUS")
        XCTAssertEqual(view.tableFileName, "SAMPLE.DB")
        XCTAssertEqual(view.additionalStrings, ["Form Title"])
        XCTAssertEqual(view.binary.size, data.count)
    }

    func testParadoxRecordDecodesNumericAndDateFields() throws {
        let data = makeNumericTable()
        let table = try ParadoxTable(data: data)

        XCTAssertEqual(table.tableName, "NUMERIC.DB")
        XCTAssertEqual(table.fields.count, 7)
        XCTAssertEqual(table.fieldNames, ["ID", "COUNT", "FACTOR", "ACTIVE", "CREATED", "SHIFT", "UPDATED"])
        let record = try XCTUnwrap(table.records.first)
        let values = record.values()

        XCTAssertEqual(values[0].value, .integer(25))
        XCTAssertEqual(values[1].value, .integer(123_456))

        if case .double(let number)? = values[2].value {
            XCTAssertEqual(number, 3.14159, accuracy: 0.00001)
        } else {
            XCTFail("Expected double value")
        }

        if case .bool(let flag)? = values[3].value {
            XCTAssertTrue(flag)
        } else {
            XCTFail("Expected logical value")
        }

        if case .date(let date)? = values[4].value {
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2023)
            XCTAssertEqual(components.month, 4)
            XCTAssertEqual(components.day, 15)
        } else {
            XCTFail("Expected date value")
        }

        if case .time(let interval)? = values[5].value {
            XCTAssertEqual(interval, 30_600, accuracy: 0.5)
        } else {
            XCTFail("Expected time value")
        }

        if case .timestamp(let timestamp)? = values[6].value {
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: timestamp)
            XCTAssertEqual(components.year, 2023)
            XCTAssertEqual(components.month, 4)
            XCTAssertEqual(components.day, 15)
            XCTAssertEqual(components.hour, 10)
            XCTAssertEqual(components.minute, 15)
            XCTAssertEqual(components.second, 30)
        } else {
            XCTFail("Expected timestamp value")
        }
    }

    func testParadoxMemoFieldDecodesThroughBlobStore() throws {
        let fm = FileManager.default
        let tempDirectory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDirectory) }

        let baseName = "Sample"
        let dbURL = tempDirectory.appendingPathComponent("Copy of \(baseName).DB")
        let mbURL = tempDirectory.appendingPathComponent("\(baseName).MB")

        let memoString = "Memo blob text!"
        let memoData = memoString.data(using: .windowsCP1252)!
        let length = memoData.count
        let lengthChunks = UInt8((length + 15) / 16)
        let remainder = UInt8(length - (Int(lengthChunks) - 1) * 16)

        var mbData = Data(repeating: 0, count: 0x2000)
        mbData[0] = 0x00
        mbData[1] = 0x01
        mbData[2] = 0x00

        let blockOffset = 0x1000
        mbData[blockOffset] = 0x03
        mbData[blockOffset + 1] = 0x01
        mbData[blockOffset + 2] = 0x00

        let entryOffset = blockOffset + 12 + 0x3F * 5
        mbData[entryOffset] = 0x15
        mbData[entryOffset + 1] = lengthChunks
        mbData[entryOffset + 2] = 0x01
        mbData[entryOffset + 3] = 0x00
        mbData[entryOffset + 4] = remainder

        let blobOffset = blockOffset + 0x150
        mbData.replaceSubrange(blobOffset..<(blobOffset + length), with: memoData)

        try mbData.write(to: mbURL)

        let fieldCount: UInt16 = 2
        let fieldLengths: [UInt8] = [4, 11]
        let recordSize: UInt16 = UInt16(fieldLengths.reduce(0) { $0 + UInt16($1) })
        let headerLength: UInt16 = 256
        let fileType: UInt8 = 0x00
        let maxTableSize: UInt8 = 0x04
        let recordCount: UInt32 = 1

        var headerArea = Data(repeating: 0, count: Int(headerLength))
        headerArea.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: recordSize.littleEndian, toByteOffset: 0, as: UInt16.self)
            buffer.storeBytes(of: headerLength.littleEndian, toByteOffset: 0x02, as: UInt16.self)
            buffer.storeBytes(of: fileType, toByteOffset: 0x04, as: UInt8.self)
            buffer.storeBytes(of: maxTableSize, toByteOffset: 0x05, as: UInt8.self)
            buffer.storeBytes(of: recordCount.littleEndian, toByteOffset: 0x06, as: UInt32.self)
            buffer.storeBytes(of: fieldCount.littleEndian, toByteOffset: 0x21, as: UInt16.self)
            buffer.storeBytes(of: UInt8(0x0C), toByteOffset: 0x39, as: UInt8.self)
        }

        let descriptorOffset = 0x78
        headerArea[descriptorOffset] = 0x01
        headerArea[descriptorOffset + 1] = fieldLengths[0]
        headerArea[descriptorOffset + 2] = 0x0C
        headerArea[descriptorOffset + 3] = fieldLengths[1]

        var cursor = descriptorOffset + fieldLengths.count * 2
        let pointerSectionLength = 4 + Int(fieldCount) * 4
        headerArea.replaceSubrange(cursor..<(cursor + pointerSectionLength), with: Data(repeating: 0, count: pointerSectionLength))
        cursor += pointerSectionLength

        let fieldNumberSectionLength = Int(fieldCount) * 2
        headerArea.replaceSubrange(cursor..<(cursor + fieldNumberSectionLength), with: Data(repeating: 0, count: fieldNumberSectionLength))
        cursor += fieldNumberSectionLength

        let tableName = Array("\(baseName).DB".utf8)
        headerArea.replaceSubrange(cursor..<(cursor + tableName.count), with: tableName)
        cursor += tableName.count
        headerArea[cursor] = 0
        headerArea[cursor + 1] = 0
        cursor += 2

        for name in ["Code", "Template"] {
            var bytes = Array(name.utf8)
            bytes.append(0)
            headerArea.replaceSubrange(cursor..<(cursor + bytes.count), with: bytes)
            cursor += bytes.count
        }

        var recordArea = Data(repeating: 0, count: 6)
        var row = Data()
        row.append(contentsOf: "CODE".utf8)

        let pointerOffsetRaw: UInt32 = UInt32(blockOffset) | 0x3F
        let pointerLength = UInt32(length)
        var pointer = Data()
        pointer.append(contentsOf: "M".utf8)
        pointer.append(contentsOf: withUnsafeBytes(of: pointerOffsetRaw.littleEndian, Array.init))
        pointer.append(contentsOf: withUnsafeBytes(of: pointerLength.littleEndian, Array.init))
        pointer.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))

        if pointer.count < Int(fieldLengths[1]) {
            pointer.append(contentsOf: repeatElement(UInt8(0), count: Int(fieldLengths[1]) - pointer.count))
        }

        row.append(pointer)
        recordArea.append(row)

        let tableData = headerArea + recordArea
        try tableData.write(to: dbURL)

        let loaded = try Data(contentsOf: dbURL)
        let table = try ParadoxTable(data: loaded, fileURL: dbURL)
        XCTAssertEqual(table.fieldNames, ["Code", "Template"])

        guard let record = table.records.first else {
            XCTFail("Expected a record")
            return
        }

        let values = record.values()
        XCTAssertEqual(values.count, 2)

        if case let .text(code)? = values[0].value {
            XCTAssertEqual(code.trimmingCharacters(in: .whitespaces), "CODE")
        } else {
            XCTFail("Expected alpha text for first field")
        }

        if case let .text(memo)? = values[1].value {
            XCTAssertEqual(memo, memoString)
        } else {
            XCTFail("Expected resolved memo text")
        }
    }

    func testParadoxGraphicFieldResolvesImageData() throws {
        let fm = FileManager.default
        let tempDirectory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDirectory) }

        let baseName = "SampleGraphic"
        let dbURL = tempDirectory.appendingPathComponent("Copy of \(baseName).DB")
        let mbURL = tempDirectory.appendingPathComponent("\(baseName).MB")

        let pngBytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
            0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
            0x35, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
            0x44, 0xAE, 0x42, 0x60, 0x82
        ]
        let imageData = Data(pngBytes)

        var mbData = Data(repeating: 0, count: 0x2000)
        mbData[0] = 0x00
        mbData[1] = 0x01
        mbData[2] = 0x00

        let blockOffset = 0x1000
        mbData[blockOffset] = 0x03
        mbData[blockOffset + 1] = 0x01
        mbData[blockOffset + 2] = 0x00

        let chunkCount = UInt8((imageData.count + 15) / 16)
        let remainder = UInt8(imageData.count % 16 == 0 ? 16 : imageData.count % 16)
        let entryOffset = blockOffset + 12 + 0x3F * 5
        mbData[entryOffset] = 0x15
        mbData[entryOffset + 1] = chunkCount
        mbData[entryOffset + 2] = 0x01
        mbData[entryOffset + 3] = 0x00
        mbData[entryOffset + 4] = remainder

        let blobOffset = blockOffset + 0x150
        mbData.replaceSubrange(blobOffset..<(blobOffset + imageData.count), with: imageData)

        try mbData.write(to: mbURL)

        let fieldCount: UInt16 = 2
        let fieldLengths: [UInt8] = [4, 11]
        let recordSize: UInt16 = UInt16(fieldLengths.reduce(0, { $0 + UInt16($1) }))
        let headerLength: UInt16 = 256
        let fileType: UInt8 = 0x00
        let maxTableSize: UInt8 = 0x04
        let recordCount: UInt32 = 1

        var headerArea = Data(repeating: 0, count: Int(headerLength))
        headerArea.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: recordSize.littleEndian, toByteOffset: 0, as: UInt16.self)
            buffer.storeBytes(of: headerLength.littleEndian, toByteOffset: 0x02, as: UInt16.self)
            buffer.storeBytes(of: fileType, toByteOffset: 0x04, as: UInt8.self)
            buffer.storeBytes(of: maxTableSize, toByteOffset: 0x05, as: UInt8.self)
            buffer.storeBytes(of: recordCount.littleEndian, toByteOffset: 0x06, as: UInt32.self)
            buffer.storeBytes(of: fieldCount.littleEndian, toByteOffset: 0x21, as: UInt16.self)
            buffer.storeBytes(of: UInt8(0x0C), toByteOffset: 0x39, as: UInt8.self)
        }

        let descriptorOffset = 0x78
        headerArea[descriptorOffset] = 0x01
        headerArea[descriptorOffset + 1] = fieldLengths[0]
        headerArea[descriptorOffset + 2] = 0x10
        headerArea[descriptorOffset + 3] = fieldLengths[1]

        var cursor = descriptorOffset + fieldLengths.count * 2
        let pointerSectionLength = 4 + Int(fieldCount) * 4
        headerArea.replaceSubrange(cursor..<(cursor + pointerSectionLength), with: Data(repeating: 0, count: pointerSectionLength))
        cursor += pointerSectionLength

        let fieldNumberSectionLength = Int(fieldCount) * 2
        headerArea.replaceSubrange(cursor..<(cursor + fieldNumberSectionLength), with: Data(repeating: 0, count: fieldNumberSectionLength))
        cursor += fieldNumberSectionLength

        let tableName = Array("\(baseName).DB".utf8)
        headerArea.replaceSubrange(cursor..<(cursor + tableName.count), with: tableName)
        cursor += tableName.count
        headerArea[cursor] = 0
        headerArea[cursor + 1] = 0
        cursor += 2

        for name in ["Code", "Picture"] {
            var bytes = Array(name.utf8)
            bytes.append(0)
            headerArea.replaceSubrange(cursor..<(cursor + bytes.count), with: bytes)
            cursor += bytes.count
        }

        var recordArea = Data(repeating: 0, count: 6)
        var row = Data()
        row.append(contentsOf: "IMG1".utf8)

        let pointerOffsetRaw: UInt32 = UInt32(blockOffset) | 0x3F
        let pointerLength = UInt32(imageData.count)
        var pointer = Data([0x00])
        pointer.append(contentsOf: withUnsafeBytes(of: pointerOffsetRaw.littleEndian, Array.init))
        pointer.append(contentsOf: withUnsafeBytes(of: pointerLength.littleEndian, Array.init))
        pointer.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        row.append(pointer)

        recordArea.append(row)

        let tableData = headerArea + recordArea
        try tableData.write(to: dbURL)

        let loaded = try Data(contentsOf: dbURL)
        let table = try ParadoxTable(data: loaded, fileURL: dbURL)
        let record = try XCTUnwrap(table.records.first)
        let values = record.values()

        if case let .image(data)? = values[1].value {
            XCTAssertEqual(data, imageData)
        } else {
            XCTFail("Expected resolved image data")
        }
    }

    // MARK: - Helpers

    private func makeMockTable() -> Data {
        let fieldCount: UInt16 = 2
        let fieldLengths: [UInt8] = [4, 6]
        let recordSize: UInt16 = UInt16(fieldLengths.reduce(0, { $0 + UInt16($1) }))
        let headerLength: UInt16 = 256 // enough space for descriptors + names
        let fileType: UInt8 = 0x00
        let maxTableSize: UInt8 = 0x04
        let recordCount: UInt32 = 2

        var headerArea = Data(repeating: 0, count: Int(headerLength))
        headerArea.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: recordSize.littleEndian, toByteOffset: 0, as: UInt16.self)
            buffer.storeBytes(of: headerLength.littleEndian, toByteOffset: 0x02, as: UInt16.self)
            buffer.storeBytes(of: fileType, toByteOffset: 0x04, as: UInt8.self)
            buffer.storeBytes(of: maxTableSize, toByteOffset: 0x05, as: UInt8.self)
            buffer.storeBytes(of: recordCount.littleEndian, toByteOffset: 0x06, as: UInt32.self)
            buffer.storeBytes(of: fieldCount.littleEndian, toByteOffset: 0x21, as: UInt16.self)
            buffer.storeBytes(of: UInt8(0x0C), toByteOffset: 0x39, as: UInt8.self)
        }

        let descriptorOffset = 0x78
        for (index, length) in fieldLengths.enumerated() {
            let base = descriptorOffset + index * 2
            headerArea[base] = 0x01 // Alpha
            headerArea[base + 1] = length
        }

        var cursor = descriptorOffset + fieldLengths.count * 2

        let pointerSectionLength = 4 + Int(fieldCount) * 4
        headerArea.replaceSubrange(cursor..<(cursor + pointerSectionLength), with: Data(repeating: 0, count: pointerSectionLength))
        cursor += pointerSectionLength

        let fieldNumberSectionLength = Int(fieldCount) * 2
        headerArea.replaceSubrange(cursor..<(cursor + fieldNumberSectionLength), with: Data(repeating: 0, count: fieldNumberSectionLength))
        cursor += fieldNumberSectionLength

        let tableName = Array("MOCK.DB".utf8)
        headerArea.replaceSubrange(cursor..<(cursor + tableName.count), with: tableName)
        cursor += tableName.count
        headerArea[cursor] = 0
        headerArea[cursor + 1] = 0
        cursor += 2

        for name in ["CODE", "DESC"] {
            var bytes = Array(name.utf8)
            bytes.append(0)
            headerArea.replaceSubrange(cursor..<(cursor + bytes.count), with: bytes)
            cursor += bytes.count
        }

        let records: [[String]] = [
            ["A001", "Widget"],
            ["A002", "Flange"]
        ]

        var recordArea = Data(repeating: 0, count: 6)
        for record in records {
            var row = Data()
            for (value, length) in zip(record, fieldLengths) {
                var bytes = Array(value.utf8)
                if bytes.count < Int(length) {
                    bytes.append(contentsOf: Array(repeating: 0x20, count: Int(length) - bytes.count))
                }
                row.append(contentsOf: bytes.prefix(Int(length)))
            }
            recordArea.append(row)
        }

        return headerArea + recordArea
    }

    private func makeNumericTable() -> Data {
        let fieldTypes: [(length: UInt8, type: UInt8, name: String)] = [
            (2, 0x03, "ID"),
            (4, 0x04, "COUNT"),
            (8, 0x06, "FACTOR"),
            (1, 0x07, "ACTIVE"),
            (4, 0x02, "CREATED"),
            (4, 0x14, "SHIFT"),
            (8, 0x15, "UPDATED")
        ]

        let fieldCount = UInt16(fieldTypes.count)
        let recordSize = UInt16(fieldTypes.reduce(0) { $0 + UInt16($1.length) })
        let headerLength: UInt16 = 288
        let fileType: UInt8 = 0x00
        let maxTableSize: UInt8 = 0x04
        let recordCount: UInt32 = 1

        var headerArea = Data(repeating: 0, count: Int(headerLength))
        headerArea.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: recordSize.littleEndian, toByteOffset: 0, as: UInt16.self)
            buffer.storeBytes(of: headerLength.littleEndian, toByteOffset: 0x02, as: UInt16.self)
            buffer.storeBytes(of: fileType, toByteOffset: 0x04, as: UInt8.self)
            buffer.storeBytes(of: maxTableSize, toByteOffset: 0x05, as: UInt8.self)
            buffer.storeBytes(of: recordCount.littleEndian, toByteOffset: 0x06, as: UInt32.self)
            buffer.storeBytes(of: fieldCount.littleEndian, toByteOffset: 0x21, as: UInt16.self)
            buffer.storeBytes(of: UInt8(0x0C), toByteOffset: 0x39, as: UInt8.self)
        }

        let descriptorOffset = 0x78
        for (index, entry) in fieldTypes.enumerated() {
            let base = descriptorOffset + index * 2
            headerArea[base] = entry.type
            headerArea[base + 1] = entry.length
        }

        var cursor = descriptorOffset + fieldTypes.count * 2

        let pointerSectionLength = 4 + Int(fieldCount) * 4
        headerArea.replaceSubrange(cursor..<(cursor + pointerSectionLength), with: Data(repeating: 0, count: pointerSectionLength))
        cursor += pointerSectionLength

        let fieldNumberSectionLength = Int(fieldCount) * 2
        headerArea.replaceSubrange(cursor..<(cursor + fieldNumberSectionLength), with: Data(repeating: 0, count: fieldNumberSectionLength))
        cursor += fieldNumberSectionLength

        let tableName = Array("NUMERIC.DB".utf8)
        headerArea.replaceSubrange(cursor..<(cursor + tableName.count), with: tableName)
        cursor += tableName.count
        headerArea[cursor] = 0
        headerArea[cursor + 1] = 0
        cursor += 2

        for entry in fieldTypes {
            var bytes = Array(entry.name.utf8)
            bytes.append(0)
            headerArea.replaceSubrange(cursor..<(cursor + bytes.count), with: bytes)
            cursor += bytes.count
        }

        var record = Data(repeating: 0, count: 6)
        record.append(paradoxEncodeShort(25))
        record.append(paradoxEncodeLong(123_456))
        record.append(paradoxEncodeDouble(3.14159))
        record.append(paradoxEncodeLogical(true))

        let createdComponents = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: 2023, month: 4, day: 15)
        let createdDate = createdComponents.date!
        record.append(paradoxEncodeDate(from: createdDate))

        let shiftMilliseconds: Int32 = 30_600_000 // 08:30:00
        record.append(paradoxEncodeTime(milliseconds: shiftMilliseconds))

        let updatedComponents = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: 2023, month: 4, day: 15, hour: 10, minute: 15, second: 30)
        let updatedDate = updatedComponents.date!
        record.append(paradoxEncodeTimestamp(from: updatedDate))

        return headerArea + record
    }

    private func paradoxDays(from date: Date) -> Int32 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: 1, month: 1, day: 1))!
        let components = calendar.dateComponents([.day], from: base, to: date)
        return Int32((components.day ?? 0) + 1)
    }

    private func paradoxEncodeShort(_ value: Int16) -> Data {
        var bytes = withUnsafeBytes(of: value.bigEndian) { Array($0) }
        if value >= 0 {
            bytes[0] |= 0x80
        } else {
            bytes[0] &= 0x7F
        }
        return Data(bytes)
    }

    private func paradoxEncodeLong(_ value: Int32) -> Data {
        var bytes = withUnsafeBytes(of: value.bigEndian) { Array($0) }
        if value >= 0 {
            bytes[0] |= 0x80
        } else {
            bytes[0] &= 0x7F
        }
        return Data(bytes)
    }

    private func paradoxEncodeDouble(_ value: Double) -> Data {
        var bitPattern = value.bitPattern
        var bytes = withUnsafeBytes(of: bitPattern) { Array($0) }
        bytes.reverse()
        if value >= 0 {
            bytes[0] |= 0x80
        } else {
            for index in bytes.indices {
                bytes[index] = ~bytes[index]
            }
        }
        return Data(bytes)
    }

    private func paradoxEncodeLogical(_ value: Bool) -> Data {
        var byte: UInt8 = value ? 1 : 0
        byte |= 0x80
        return Data([byte])
    }

    private func paradoxEncodeDate(from date: Date) -> Data {
        paradoxEncodeLong(paradoxDays(from: date))
    }

    private func paradoxEncodeTime(milliseconds: Int32) -> Data {
        paradoxEncodeLong(milliseconds)
    }

    private func paradoxEncodeTimestamp(from date: Date) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let days = Double(paradoxDays(from: date))
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let seconds = Double(components.hour ?? 0) * 3600
            + Double(components.minute ?? 0) * 60
            + Double(components.second ?? 0)
            + Double(components.nanosecond ?? 0) / 1_000_000_000
        let doubleValue = days + (seconds / 86_400.0)
        return paradoxEncodeDouble(doubleValue)
    }
}
