import Foundation

final class ParadoxBlobStore {
    private let mbFiles: [URL]
    private var cache: [URL: Data] = [:]
    private let fileManager = FileManager.default

    init?(tableURL: URL, declaredTableName: String?) {
        let directory = tableURL.deletingLastPathComponent()
        guard let directoryContents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }

        let mbFilesInDirectory = directoryContents.filter { $0.pathExtension.caseInsensitiveCompare("MB") == .orderedSame }
        guard !mbFilesInDirectory.isEmpty else {
            return nil
        }

        let tableBaseName = tableURL.deletingPathExtension().lastPathComponent
        var candidateNames: [String] = []
        candidateNames.append(contentsOf: ParadoxBlobStore.generateCandidateNames(from: tableBaseName))
        if let declaredTableName {
            let declaredBase = URL(fileURLWithPath: declaredTableName).deletingPathExtension().lastPathComponent
            candidateNames.append(contentsOf: ParadoxBlobStore.generateCandidateNames(from: declaredBase))
        }

        var seenBases: Set<String> = []
        candidateNames = candidateNames.filter { base in
            let lowering = base.lowercased()
            if seenBases.contains(lowering) {
                return false
            }
            seenBases.insert(lowering)
            return true
        }

        var prioritized: [URL] = []
        let lookup = Dictionary(uniqueKeysWithValues: mbFilesInDirectory.map { ($0.deletingPathExtension().lastPathComponent.lowercased(), $0) })

        for candidate in candidateNames {
            let key = candidate.lowercased()
            if let match = lookup[key] {
                prioritized.append(match)
            }
        }

        // Fallback to considering every MB file in the directory if no heuristic match succeeds.
        if prioritized.isEmpty {
            prioritized = mbFilesInDirectory
        }

        self.mbFiles = prioritized
    }

    func resolveMemoField(bytes: Data, encoding: String.Encoding) -> String? {
        guard let (leader, blob) = resolveBlob(bytes: bytes) else { return nil }
        if let blob, let decoded = decodeMemoString(blob, encoding: encoding) {
            return decoded
        }
        if let fallback = decodeMemoString(leader, encoding: encoding) {
            return fallback
        }
        return leader.isEmpty ? "" : nil
    }

    func resolveBinaryField(bytes: Data) -> Data? {
        guard let (leader, blob) = resolveBlob(bytes: bytes) else { return nil }
        if let blob {
            return blob
        }
        return leader.isEmpty ? nil : leader
    }

    private func loadBlob(blockOffset: Int, index: UInt8, declaredLength: UInt32) -> Data? {
        for url in mbFiles {
            guard let data = dataForMB(at: url), blockOffset + 9 <= data.count else { continue }
            let blockType = data[blockOffset]
            if index == 0xFF {
                guard blockType == 0x02 else { continue }
                let chunkCount = Int(readUInt16LE(data, offset: blockOffset + 1))
                let blockLength = chunkCount * 0x1000
                let blobLength = Int(readUInt32LE(data, offset: blockOffset + 3))
                let payloadStart = blockOffset + 9
                let available = max(0, blockLength - 9)
                let desired = blobLength > 0 ? blobLength : Int(declaredLength)
                let payloadLength = min(max(desired, 0), available)
                guard payloadLength > 0, payloadStart + payloadLength <= data.count else { continue }
                let range = payloadStart..<(payloadStart + payloadLength)
                return Data(data[range])
            } else {
                guard blockType == 0x03 else { continue }
                let entryOffset = blockOffset + 12 + Int(index) * 5
                guard entryOffset + 5 <= data.count else { continue }
                let entry = data[entryOffset..<(entryOffset + 5)]
                if entry.allSatisfy({ $0 == 0 }) {
                    continue
                }
                let dataOffsetWithinBlock = Int(entry[entry.startIndex]) * 16
                let chunkCount = Int(entry[entry.startIndex + 1])
                let remainder = Int(entry[entry.startIndex + 4])
                let normalizedRemainder = (remainder == 0 && chunkCount > 0) ? 16 : remainder
                let entryLength = max(chunkCount - 1, 0) * 16 + normalizedRemainder
                guard entryLength > 0 else { continue }
                let targetLength = declaredLength > 0 ? Int(declaredLength) : entryLength
                let payloadLength = min(targetLength, entryLength)
                let payloadStart = blockOffset + dataOffsetWithinBlock
                guard payloadStart + payloadLength <= data.count, payloadStart >= blockOffset else {
                    continue
                }
                let range = payloadStart..<(payloadStart + payloadLength)
                return Data(data[range])
            }
        }
        return nil
    }

    private func resolveBlob(bytes: Data) -> (Data, Data?)? {
        guard !bytes.isEmpty else { return (Data(), nil) }
        let pointerLength = min(10, bytes.count)
        guard pointerLength == 10 else {
            return (Data(bytes), nil)
        }

        let leader = Data(bytes.prefix(bytes.count - pointerLength))
        let pointerBytes = Array(bytes.suffix(pointerLength))

        let offsetRaw = readUInt32BytesLE(pointerBytes, start: 0)
        let lengthRaw = readUInt32BytesLE(pointerBytes, start: 4)
        let index = UInt8(truncatingIfNeeded: offsetRaw & 0xFF)
        let blockOffset = Int(offsetRaw & ~UInt32(0xFF))

        if offsetRaw == 0 {
            return (leader, nil)
        }

        if let blobData = loadBlob(blockOffset: blockOffset, index: index, declaredLength: lengthRaw) {
            return (leader, blobData)
        }
        return (leader, nil)
    }

    private func dataForMB(at url: URL) -> Data? {
        if let cached = cache[url] {
            return cached
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        cache[url] = data
        return data
    }

    private func decodeMemoString(_ data: Data, encoding: String.Encoding) -> String? {
        var trimmed = data
        while let last = trimmed.last, last == 0 {
            trimmed.removeLast()
        }
        if trimmed.isEmpty {
            return ""
        }
        if let string = String(data: trimmed, encoding: encoding) {
            return string
        }
        if let string = String(data: trimmed, encoding: .windowsCP1252) {
            return string
        }
        if let string = String(data: trimmed, encoding: .isoLatin1) {
            return string
        }
        if let string = String(data: trimmed, encoding: .ascii) {
            return string
        }
        return nil
    }

    private static func generateCandidateNames(from base: String) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        func add(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = trimmed.lowercased()
            if !trimmed.isEmpty && !seen.contains(lowered) {
                ordered.append(trimmed)
                seen.insert(lowered)
            }
        }

        add(base)

        if let range = base.range(of: #" \(\d+\)$"#, options: .regularExpression) {
            var trimmed = base
            trimmed.removeSubrange(range)
            add(trimmed)
        }

        let lower = base.lowercased()
        if lower.hasPrefix("copy of ") {
            let stripped = String(base.dropFirst("Copy of ".count))
            add(stripped)
            if let range = stripped.range(of: #" \(\d+\)$"#, options: .regularExpression) {
                var trimmed = stripped
                trimmed.removeSubrange(range)
                add(trimmed)
            }
        }

        return ordered
    }
}

private func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
    guard offset + 2 <= data.count else { return 0 }
    let bytes = Array(data[offset..<(offset + 2)])
    return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
}

private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
    guard offset + 4 <= data.count else { return 0 }
    let bytes = Array(data[offset..<(offset + 4)])
    return readUInt32BytesLE(bytes, start: 0)
}

@inline(__always)
private func readUInt32BytesLE(_ bytes: [UInt8], start: Int) -> UInt32 {
    guard start + 4 <= bytes.count else { return 0 }
    return UInt32(bytes[start])
        | (UInt32(bytes[start + 1]) << 8)
        | (UInt32(bytes[start + 2]) << 16)
        | (UInt32(bytes[start + 3]) << 24)
}
