import Foundation

public struct CalsHeaderRecord: Hashable, Sendable {
    public let name: String
    public let value: String
}

public enum CalsRasterError: Error, LocalizedError {
    case headerNotFound
    case truncatedHeader
    case missingField(String)
    case invalidField(String)
    case unsupportedRasterType(Int)

    public var errorDescription: String? {
        switch self {
        case .headerNotFound:
            return "Unable to locate a CALS Type 1 header."
        case .truncatedHeader:
            return "CALS header appears to be truncated."
        case .missingField(let field):
            return "CALS header missing required field \(field)."
        case .invalidField(let field):
            return "CALS header contains an invalid value for \(field)."
        case .unsupportedRasterType(let type):
            return "CALS raster type \(type) is not supported."
        }
    }
}

public struct CalsRasterDocument: Sendable {
    public static let headerLength = 2048
    public static let recordLength = 128
    private static let headerSentinel = Data("srcdocid:".utf8)

    public let headerOffset: Int
    public let rawHeader: Data
    public let headerRecords: [CalsHeaderRecord]
    public let widthPixels: Int
    public let heightPixels: Int
    public let dpi: Int
    public let rasterType: Int
    public let orientation: String
    public let rawImageData: Data

    public init(data: Data, suggestedHeaderOffset: Int? = nil) throws {
        let offset = try Self.locateHeader(in: data, suggestedOffset: suggestedHeaderOffset)
        guard offset + Self.headerLength <= data.count else {
            throw CalsRasterError.truncatedHeader
        }

        let headerSlice = data.subdata(in: offset..<(offset + Self.headerLength))
        self.rawHeader = headerSlice
        self.headerOffset = offset

        let decodedRecords = Self.decodeRecords(from: headerSlice)
        self.headerRecords = decodedRecords.records

        guard let rtypeString = decodedRecords.map["rtype"] else {
            throw CalsRasterError.missingField("rtype")
        }
        guard let parsedType = Int(rtypeString) else {
            throw CalsRasterError.invalidField("rtype")
        }
        guard parsedType == 1 else {
            throw CalsRasterError.unsupportedRasterType(parsedType)
        }
        self.rasterType = parsedType

        guard let rpelcntString = decodedRecords.map["rpelcnt"] else {
            throw CalsRasterError.missingField("rpelcnt")
        }
        let dimensions = rpelcntString.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
        guard dimensions.count == 2,
              let width = Int(dimensions[0], radix: 10),
              let height = Int(dimensions[1], radix: 10) else {
            throw CalsRasterError.invalidField("rpelcnt")
        }
        self.widthPixels = width
        self.heightPixels = height

        guard let densityString = decodedRecords.map["rdensty"], let parsedDensity = Int(densityString) else {
            throw CalsRasterError.invalidField("rdensty")
        }
        self.dpi = parsedDensity

        self.orientation = decodedRecords.map["rorient"] ?? ""

        let payloadStart = offset + Self.headerLength
        self.rawImageData = Data(data[payloadStart..<data.count])
    }

    public func value(for key: String) -> String? {
        let lowered = key.lowercased()
        return headerRecords.first(where: { $0.name.lowercased() == lowered })?.value
    }

    public func makeTiffData() -> Data {
        let imageOffset = 8
        let imageSize = rawImageData.count
        let xResolutionOffset = imageOffset + imageSize
        let yResolutionOffset = xResolutionOffset + 8
        let ifdOffset = yResolutionOffset + 8

        var buffer = Data()
        buffer.reserveCapacity(ifdOffset + 2 + (12 * 12) + 4)

        buffer.append(contentsOf: [0x49, 0x49, 0x2A, 0x00])
        buffer.appendLittleEndian(UInt32(ifdOffset))
        buffer.append(rawImageData)
        buffer.appendLittleEndian(UInt32(dpi))
        buffer.appendLittleEndian(UInt32(1))
        buffer.appendLittleEndian(UInt32(dpi))
        buffer.appendLittleEndian(UInt32(1))

        var ifdData = Data()
        let tags: [TiffTag] = [
            TiffTag(tag: 256, type: 3, value: UInt32(widthPixels)),
            TiffTag(tag: 257, type: 3, value: UInt32(heightPixels)),
            TiffTag(tag: 258, type: 3, value: 1),
            TiffTag(tag: 259, type: 3, value: 4),
            TiffTag(tag: 262, type: 3, value: 0),
            TiffTag(tag: 266, type: 3, value: 1),
            TiffTag(tag: 273, type: 4, value: UInt32(imageOffset)),
            TiffTag(tag: 278, type: 4, value: UInt32(heightPixels)),
            TiffTag(tag: 279, type: 4, value: UInt32(imageSize)),
            TiffTag(tag: 282, type: 5, value: UInt32(xResolutionOffset)),
            TiffTag(tag: 283, type: 5, value: UInt32(yResolutionOffset)),
            TiffTag(tag: 296, type: 3, value: 2)
        ]

        ifdData.appendLittleEndian(UInt16(tags.count))
        for tag in tags {
            ifdData.appendLittleEndian(UInt16(tag.tag))
            ifdData.appendLittleEndian(UInt16(tag.type))
            ifdData.appendLittleEndian(UInt32(tag.count))
            ifdData.appendLittleEndian(tag.value)
        }
        ifdData.append(contentsOf: [0, 0, 0, 0])

        buffer.append(ifdData)
        return buffer
    }

    private struct DecodedHeader {
        let records: [CalsHeaderRecord]
        let map: [String: String]
    }

    static func locateHeader(in data: Data, suggestedOffset: Int?) throws -> Int {
        if let offset = suggestedOffset {
            guard offset >= 0, offset + headerLength <= data.count else {
                throw CalsRasterError.truncatedHeader
            }
            return offset
        }

        guard let range = data.range(of: headerSentinel) else {
            throw CalsRasterError.headerNotFound
        }
        return range.lowerBound
    }

    private static func decodeRecords(from header: Data) -> DecodedHeader {
        var records: [CalsHeaderRecord] = []
        records.reserveCapacity(headerLength / recordLength)
        var map: [String: String] = [:]

        var cursor = 0
        while cursor < header.count {
            let upperBound = min(cursor + recordLength, header.count)
            let slice = header.subdata(in: cursor..<upperBound)
            cursor = upperBound

            guard let string = String(data: slice, encoding: .ascii) else { continue }
            let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: " \u{0000}.\r\n\t"))
            guard !trimmed.isEmpty, let colonIndex = trimmed.firstIndex(of: ":") else { continue }

            let name = trimmed[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let valueStart = trimmed.index(after: colonIndex)
            let value = trimmed[valueStart...].trimmingCharacters(in: .whitespaces)

            let record = CalsHeaderRecord(name: String(name), value: String(value))
            records.append(record)
            map[record.name.lowercased()] = record.value
        }

        return DecodedHeader(records: records, map: map)
    }

    private struct TiffTag {
        let tag: UInt16
        let type: UInt16
        let count: UInt32 = 1
        let value: UInt32
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
