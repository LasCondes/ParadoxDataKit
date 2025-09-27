import Foundation

/// A contiguous printable ASCII run detected in binary data.
public struct GenericBinaryAsciiSegment: Hashable {
    public let offset: Int
    public let text: String

    public init(offset: Int, text: String) {
        self.offset = offset
        self.text = text
    }
}

/// Lightweight wrapper that preserves arbitrary binary data while offering convenience previews.
public struct GenericBinaryFile {
    public let size: Int
    public let headerPreview: Data
    public let data: Data

    public init(data: Data, previewLength: Int = 64) {
        self.size = data.count
        self.headerPreview = Data(data.prefix(previewLength))
        self.data = data
    }

    /// Returns a traditional hex + ASCII dump of the first `prefixLength` bytes.
    public func hexDump(prefixLength: Int = 64) -> String {
        let bytes = data.prefix(prefixLength)
        guard !bytes.isEmpty else { return "" }

        var output: [String] = []
        var offset = 0
        let chunkSize = 16

        while offset < bytes.count {
            let upperBound = min(offset + chunkSize, bytes.count)
            let lineSlice = bytes[offset..<upperBound]
            let hexBytes = lineSlice.map { String(format: "%02X", $0) }
            let padding = max(0, (chunkSize - hexBytes.count))
            let hexPart = hexBytes.joined(separator: " ") + String(repeating: "   ", count: padding)
            let asciiPart = lineSlice.map { byte -> Character in
                guard byte >= 0x20, byte < 0x7F, let scalar = UnicodeScalar(Int(byte)) else {
                    return "."
                }
                return Character(scalar)
            }
            let offsetString = String(format: "%08X", offset)
            output.append("\(offsetString)  \(hexPart) |\(String(asciiPart))|")
            offset += chunkSize
        }

        return output.joined(separator: "\n")
    }

    /// Detects printable ASCII sequences near the start of the data for friendlier previews.
    /// - Parameters:
    ///   - minLength: Minimum run length to include.
    ///   - prefixLength: Portion of the file (in bytes) to scan.
    /// - Returns: Offsets and strings for the detected runs.
    public func asciiSegments(minLength: Int = 4, prefixLength: Int = 512) -> [GenericBinaryAsciiSegment] {
        guard minLength > 0, prefixLength > 0 else { return [] }

        let window = data.prefix(prefixLength)
        guard !window.isEmpty else { return [] }

        var segments: [GenericBinaryAsciiSegment] = []
        var currentStart: Int?
        var buffer: [UInt8] = []

        func flushCurrent() {
            guard let start = currentStart, buffer.count >= minLength else {
                buffer.removeAll(keepingCapacity: true)
                currentStart = nil
                return
            }

            let string = String(decoding: buffer, as: UTF8.self)
            segments.append(GenericBinaryAsciiSegment(offset: start, text: string))

            buffer.removeAll(keepingCapacity: true)
            currentStart = nil
        }

        for (index, byte) in window.enumerated() {
            let isPrintableASCII = byte >= 0x20 && byte <= 0x7E
            if isPrintableASCII {
                if currentStart == nil {
                    currentStart = index
                }
                buffer.append(byte)
            } else {
                flushCurrent()
            }
        }

        flushCurrent()

        return segments
    }
}

extension GenericBinaryFile: CustomStringConvertible {
    public var description: String {
        "Generic binary file (\(size) bytes)"
    }
}
