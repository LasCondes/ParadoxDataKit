import Foundation

public struct ParadoxIndex {
    public enum Kind: String {
        case primary
        case secondary
    }

    public struct Header {
        public let recordLength: UInt16
        public let headerLength: UInt16
        public let fileType: UInt8
        public let blockSizeCode: UInt8
        public let recordCount: UInt32
        public let blocksInUse: UInt16
        public let totalBlocks: UInt16
        public let firstDataBlock: UInt16
        public let lastBlockInUse: UInt16
        public let rootBlockNumber: UInt16
        public let levelCount: UInt8
        public let fieldCount: UInt8

        public var blockSize: Int {
            max(1, Int(blockSizeCode)) * 1024
        }
    }

    public struct BlockSummary: Identifiable {
        public struct Record: Identifiable {
            public let id: Int
            public let keyHex: String
            public let childBlockNumber: Int
            public let statistics: Int
            public let reserved: Int
        }

        public let id: Int
        public let nextBlock: Int
        public let previousBlock: Int
        public let recordCount: Int
        public let records: [Record]

        public var isEmpty: Bool { recordCount == 0 }
    }

    public let kind: Kind
    public let header: Header
    public let blocks: [BlockSummary]
    public let totalBlocksReported: Int
    public let blocksParsedLimit: Int

    public init(data: Data, kind: Kind) throws {
        guard data.count >= 2048 else {
            throw ParadoxIndexError.fileTooSmall
        }

        self.kind = kind

        let recordLength = BinaryDataReader.readUInt16(from: data, at: 0x0000) ?? 0
        let headerLength = BinaryDataReader.readUInt16(from: data, at: 0x0002) ?? 0
        let fileType = BinaryDataReader.readUInt8(from: data, at: 0x0004) ?? 0
        let blockSizeCode = BinaryDataReader.readUInt8(from: data, at: 0x0005) ?? 0
        let recordCount = BinaryDataReader.readUInt32(from: data, at: 0x0006) ?? 0
        let blocksInUse = BinaryDataReader.readUInt16(from: data, at: 0x000A) ?? 0
        let totalBlocks = BinaryDataReader.readUInt16(from: data, at: 0x000C) ?? 0
        let firstDataBlock = BinaryDataReader.readUInt16(from: data, at: 0x000E) ?? 0
        let lastBlockInUse = BinaryDataReader.readUInt16(from: data, at: 0x0010) ?? 0
        let rootBlock = BinaryDataReader.readUInt16(from: data, at: 0x001E) ?? 0
        let levelCount = BinaryDataReader.readUInt8(from: data, at: 0x0020) ?? 0
        let fieldCount = BinaryDataReader.readUInt8(from: data, at: 0x0021) ?? 0

        let header = Header(
            recordLength: recordLength,
            headerLength: headerLength,
            fileType: fileType,
            blockSizeCode: blockSizeCode,
            recordCount: recordCount,
            blocksInUse: blocksInUse,
            totalBlocks: totalBlocks,
            firstDataBlock: firstDataBlock,
            lastBlockInUse: lastBlockInUse,
            rootBlockNumber: rootBlock,
            levelCount: levelCount,
            fieldCount: fieldCount
        )

        self.header = header

        let blockSize = max(1, header.blockSize)
        let declaredHeaderLength = header.headerLength == 0 ? 2048 : Int(header.headerLength)
        let headerLengthBytes = min(declaredHeaderLength, data.count)
        let availableDataBytes = max(0, data.count - headerLengthBytes)
        let computedTotalBlocks = availableDataBytes / blockSize
        let blockCount = Int(header.totalBlocks == 0 ? UInt16(computedTotalBlocks) : header.totalBlocks)
        self.totalBlocksReported = blockCount

        let maxBlocksToParse = min(blockCount, 64)
        var parsedBlocks: [BlockSummary] = []
        parsedBlocks.reserveCapacity(maxBlocksToParse)

        let blockRecordLength = Int(header.recordLength)
        let keyLength = max(0, blockRecordLength - 6)

        guard blockRecordLength >= 6 else {
            self.blocks = []
            self.blocksParsedLimit = 0
            return
        }

        if blockCount == 0 {
            self.blocks = []
            self.blocksParsedLimit = 0
            return
        }

        for blockNumber in 1...maxBlocksToParse {
            let blockOffset = headerLengthBytes + (blockNumber - 1) * blockSize
            guard blockOffset + blockSize <= data.count else { break }

            let blockData = Data(data[blockOffset..<(blockOffset + blockSize)])
            let nextBlock = Int(BinaryDataReader.readUInt16(from: blockData, at: 0x0000) ?? 0)
            let previousBlock = Int(BinaryDataReader.readUInt16(from: blockData, at: 0x0002) ?? 0)
            let lastOffsetRaw = BinaryDataReader.readUInt16(from: blockData, at: 0x0004) ?? 0
            let lastOffset = Int(Int16(bitPattern: lastOffsetRaw))
            let recordsInBlock = ParadoxIndex.recordCount(inBlockWithLastOffset: lastOffset, recordLength: blockRecordLength)

            var records: [BlockSummary.Record] = []
            if recordsInBlock > 0 {
                var cursor = 0x0006
                for recordIndex in 0..<recordsInBlock {
                    guard cursor + blockRecordLength <= blockData.count else { break }
                    let recordSlice = blockData[cursor..<(cursor + blockRecordLength)]
                    let keyData = Data(recordSlice.prefix(keyLength))
                    let tail = recordSlice.suffix(6)
                    let childBlock = ParadoxIndex.decodeIndexShort(from: tail.prefix(2))
                    let statistics = ParadoxIndex.decodeIndexShort(from: tail.dropFirst(2).prefix(2))
                    let reserved = ParadoxIndex.decodeIndexShort(from: tail.suffix(2))
                    let keyHex = ParadoxIndex.hexString(from: keyData)
                    records.append(
                        BlockSummary.Record(
                            id: recordIndex,
                            keyHex: keyHex,
                            childBlockNumber: childBlock,
                            statistics: statistics,
                            reserved: reserved
                        )
                    )
                    cursor += blockRecordLength
                    if records.count >= 12 { break }
                }
            }

            let summary = BlockSummary(
                id: blockNumber,
                nextBlock: nextBlock,
                previousBlock: previousBlock,
                recordCount: recordsInBlock,
                records: records
            )
            parsedBlocks.append(summary)
        }

        self.blocksParsedLimit = parsedBlocks.count
        self.blocks = parsedBlocks
    }

    private static func recordCount(inBlockWithLastOffset lastOffset: Int, recordLength: Int) -> Int {
        guard recordLength > 0 else { return 0 }
        if lastOffset < 0 {
            return 0
        }
        return (lastOffset / recordLength) + 1
    }

    private static func decodeIndexShort(from bytes: Data) -> Int {
        guard bytes.count >= 2 else { return 0 }
        var tmp = [UInt8](bytes.prefix(2))
        if tmp[0] & 0x80 != 0 {
            tmp[0] &= 0x7F
        } else if tmp.contains(where: { $0 != 0 }) {
            tmp[0] |= 0x80
        } else {
            return 0
        }
        let value = Int16(bitPattern: UInt16(tmp[0]) << 8 | UInt16(tmp[1]))
        return Int(value)
    }

    private static func hexString(from data: Data) -> String {
        guard !data.isEmpty else { return "<empty>" }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

public enum ParadoxIndexError: Error {
    case fileTooSmall
}
