import Foundation

public struct SpicerSMFDocument: Sendable {
    public let containerHeader: Data
    public let rasterDocument: CalsRasterDocument

    public var signature: String? {
        guard !containerHeader.isEmpty else { return nil }
        let prefix = containerHeader.prefix(16)
        let string = String(bytes: prefix, encoding: .ascii) ?? ""
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: " \u{0000}\r\n\t"))
        return trimmed.isEmpty ? nil : trimmed
    }

    public init(data: Data) throws {
        let headerOffset = try CalsRasterDocument.locateHeader(in: data, suggestedOffset: nil)
        self.containerHeader = Data(data.prefix(headerOffset))
        self.rasterDocument = try CalsRasterDocument(data: data, suggestedHeaderOffset: headerOffset)
    }
}
