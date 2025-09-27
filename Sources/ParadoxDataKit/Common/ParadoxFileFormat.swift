import Foundation

/// Known Borland Paradox-related file types that the kit can inspect.
public enum ParadoxFileFormat: CaseIterable, Sendable {
    case paradoxTable
    case paradoxQuery
    case paradoxReport
    case paradoxForm
    case paradoxFamily
    case paradoxScript
    case spreadsheet
    case snapshot
    case unknown

    /// Attempts to infer the Paradox-related file type from the provided URL.
    /// - Parameter url: The file location to inspect.
    /// - Returns: The best-matching `ParadoxFileFormat` for the file extension.
    public static func infer(from url: URL) -> ParadoxFileFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "db":
            return .paradoxTable
        case "qbe":
            return .paradoxQuery
        case "rsl":
            return .paradoxReport
        case "tv":
            return .paradoxForm
        case "fam":
            return .paradoxFamily
        case "ssl", "sdl":
            return .paradoxScript
        case "xls", "xlsx":
            return .spreadsheet
        case "bak", "tmp":
            return .snapshot
        default:
            return .unknown
        }
    }

    /// The canonical file extension for the format, when known.
    public var preferredFileExtension: String? {
        switch self {
        case .paradoxTable: return "db"
        case .paradoxQuery: return "qbe"
        case .paradoxReport: return "rsl"
        case .paradoxForm: return "tv"
        case .paradoxFamily: return "fam"
        case .paradoxScript: return "ssl"
        case .spreadsheet: return "xls"
        case .snapshot: return nil
        case .unknown: return nil
        }
    }

    /// A user-facing description for the file format.
    public var description: String {
        switch self {
        case .paradoxTable:
            return "Paradox table"
        case .paradoxQuery:
            return "Paradox QBE query"
        case .paradoxReport:
            return "Paradox report"
        case .paradoxForm:
            return "Paradox form"
        case .paradoxFamily:
            return "Paradox family table"
        case .paradoxScript:
            return "Paradox script"
        case .spreadsheet:
            return "Spreadsheet"
        case .snapshot:
            return "Snapshot"
        case .unknown:
            return "Unknown"
        }
    }
}
