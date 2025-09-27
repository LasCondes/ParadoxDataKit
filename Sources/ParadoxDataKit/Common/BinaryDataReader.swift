import Foundation

struct BinaryDataReader {
    private let data: Data
    private(set) var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func seek(to newOffset: Int) throws {
        guard newOffset >= 0, newOffset <= data.count else {
            throw ReaderError.invalidSeek(newOffset)
        }
        offset = newOffset
    }

    mutating func skip(_ count: Int) throws {
        try seek(to: offset + count)
    }

    mutating func readUInt8() throws -> UInt8 {
        let value: UInt8 = try readInteger()
        return value
    }

    mutating func readUInt16() throws -> UInt16 {
        let value: UInt16 = try readInteger()
        return value
    }

    mutating func readUInt32() throws -> UInt32 {
        let value: UInt32 = try readInteger()
        return value
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0 else {
            throw ReaderError.invalidRead(count)
        }
        guard offset + count <= data.count else {
            throw ReaderError.insufficientBytes(requested: count, remaining: data.count - offset)
        }
        let slice = data[offset..<(offset + count)]
        offset += count
        return Data(slice)
    }

    static func readUInt16(from data: Data, at index: Int) -> UInt16? {
        guard index >= 0, index + 2 <= data.count else {
            return nil
        }
        return data.withUnsafeBytes { buffer -> UInt16? in
            guard let base = buffer.baseAddress else { return nil }
            let pointer = base.advanced(by: index).assumingMemoryBound(to: UInt16.self)
            return UInt16(littleEndian: pointer.pointee)
        }
    }

    static func readUInt32(from data: Data, at index: Int) -> UInt32? {
        guard index >= 0, index + 4 <= data.count else {
            return nil
        }
        return data.withUnsafeBytes { buffer -> UInt32? in
            guard let base = buffer.baseAddress else { return nil }
            let pointer = base.advanced(by: index).assumingMemoryBound(to: UInt32.self)
            return UInt32(littleEndian: pointer.pointee)
        }
    }

    enum ReaderError: Error, LocalizedError {
        case invalidSeek(Int)
        case invalidRead(Int)
        case insufficientBytes(requested: Int, remaining: Int)

        var errorDescription: String? {
            switch self {
            case .invalidSeek(let newOffset):
                return "Attempted to seek to \(newOffset), which is outside the readable range."
            case .invalidRead(let count):
                return "Requested \(count) bytes, but count must be positive."
            case .insufficientBytes(let requested, let remaining):
                return "Requested \(requested) bytes, but only \(remaining) remain."
            }
        }
    }

    private mutating func readInteger<T>() throws -> T where T: FixedWidthInteger {
        let byteCount = MemoryLayout<T>.size
        guard offset + byteCount <= data.count else {
            throw ReaderError.insufficientBytes(requested: byteCount, remaining: data.count - offset)
        }
        let value = data.withUnsafeBytes { buffer -> T in
            let pointer = buffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: T.self)
            return pointer.pointee
        }
        offset += byteCount
        return T(littleEndian: value)
    }
}
