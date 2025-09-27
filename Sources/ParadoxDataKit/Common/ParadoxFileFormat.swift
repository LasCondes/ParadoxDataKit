import Foundation

/// Known Borland Paradox-related file types that the kit can inspect.
public enum ParadoxFileFormat: CaseIterable, Sendable {
    case paradoxTable
    case paradoxQuery
    case paradoxReport
    case paradoxForm
    case paradoxFamily
    case paradoxIndexPrimary
    case paradoxIndexSecondary
    case paradoxSecondaryIndexData
    case paradoxScript
    case spreadsheet
    case snapshot
    case calsRaster
    case spicerSmf
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
        case "px":
            return .paradoxIndexPrimary
        case _ where ext.hasPrefix("x"):
            return .paradoxSecondaryIndexData
        case _ where ext.hasPrefix("y"):
            return .paradoxIndexSecondary
        case "ssl", "sdl":
            return .paradoxScript
        case "clf", "cal", "cals":
            return .calsRaster
        case "smf":
            return .spicerSmf
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
        case .paradoxIndexPrimary: return "px"
        case .paradoxIndexSecondary: return nil
        case .paradoxSecondaryIndexData: return nil
        case .paradoxScript: return "ssl"
        case .spreadsheet: return "xls"
        case .snapshot: return nil
        case .calsRaster: return "clf"
        case .spicerSmf: return "smf"
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
        case .paradoxIndexPrimary:
            return "Paradox primary index"
        case .paradoxIndexSecondary:
            return "Paradox secondary index"
        case .paradoxSecondaryIndexData:
            return "Paradox secondary index data"
        case .paradoxScript:
            return "Paradox script"
        case .spreadsheet:
            return "Spreadsheet"
        case .snapshot:
            return "Snapshot"
        case .calsRaster:
            return "CALS raster image"
        case .spicerSmf:
            return "Spicer SMF container"
        case .unknown:
            return "Unknown"
        }
    }
}
