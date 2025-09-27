import Foundation

/// Represents a file that has been parsed by `ParadoxFileReader`.
public struct ParadoxFile {
    public let url: URL?
    public let format: ParadoxFileFormat
    public let size: Int
    public let details: ParadoxFileDetails

    public init(url: URL?, format: ParadoxFileFormat, size: Int, details: ParadoxFileDetails) {
        self.url = url
        self.format = format
        self.size = size
        self.details = details
    }
}

/// Parsed file content variants that Paradox supports.
public enum ParadoxFileDetails {
    case paradoxTable(ParadoxTable)
    case paradoxQuery(ParadoxQuery)
    case paradoxTableView(ParadoxTableView)
    case binary(GenericBinaryFile)
}

/// Errors that may occur while loading or interpreting Paradox files.
public enum ParadoxFileReaderError: Error, LocalizedError {
    case unsupportedFormat(ParadoxFileFormat)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "No parser available for files tagged as \(format.description)."
        }
    }
}

/// Convenience APIs for loading Paradox-related files from disk or raw data.
public enum ParadoxFileReader {
    /// Loads and parses a file from disk.
    ///
    /// - Parameter url: Location of the file to load.
    /// - Returns: A `ParadoxFile` describing the parsed content.
    public static func load(from url: URL) throws -> ParadoxFile {
        let data = try Data(contentsOf: url)
        let format = ParadoxFileFormat.infer(from: url)
        let details = try parse(data: data, format: format, sourceURL: url)
        return ParadoxFile(url: url, format: format, size: data.count, details: details)
    }

    /// Parses raw data using an explicitly provided file type.
    ///
    /// - Parameters:
    ///   - data: In-memory file data.
    ///   - suggestedFormat: The expected Paradox-related file type for the data.
    /// - Returns: A `ParadoxFile` describing the parsed content.
    public static func load(data: Data, suggestedFormat: ParadoxFileFormat) throws -> ParadoxFile {
        let details = try parse(data: data, format: suggestedFormat, sourceURL: nil)
        return ParadoxFile(url: nil, format: suggestedFormat, size: data.count, details: details)
    }

    private static func parse(data: Data, format: ParadoxFileFormat, sourceURL: URL?) throws -> ParadoxFileDetails {
        switch format {
        case .paradoxTable:
            return .paradoxTable(try ParadoxTable(data: data, fileURL: sourceURL))
        case .paradoxQuery:
            return .paradoxQuery(ParadoxQuery(data: data))
        case .paradoxForm:
            return .paradoxTableView(try ParadoxTableView(data: data))
        case .paradoxReport, .paradoxFamily, .paradoxScript, .spreadsheet, .snapshot, .unknown:
            return .binary(GenericBinaryFile(data: data))
        }
    }
}
