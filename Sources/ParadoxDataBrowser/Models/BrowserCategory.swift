import Foundation
import ParadoxDataKit

enum ParadoxBrowserCategory: CaseIterable, Identifiable {
    case tables
    case queries
    case reports
    case forms
    case families
    case indexes
    case scripts
    case images
    case supporting
    case other

    var id: String { rawValue }

    private var rawValue: String {
        switch self {
        case .tables: return "tables"
        case .queries: return "queries"
        case .reports: return "reports"
        case .forms: return "forms"
        case .families: return "families"
        case .indexes: return "indexes"
        case .scripts: return "scripts"
        case .images: return "images"
        case .supporting: return "supporting"
        case .other: return "other"
        }
    }

    var displayName: String {
        switch self {
        case .tables: return "Tables (.DB)"
        case .queries: return "Queries (.QBE)"
        case .reports: return "Reports (.RSL)"
        case .forms: return "Table Views (.TV)"
        case .families: return "Family Tables (.FAM)"
        case .indexes: return "Indexes (.PX/.Xnn/.Ynn)"
        case .scripts: return "Scripts (.SSL/.SDL)"
        case .images: return "Images & Graphics"
        case .supporting: return "Supporting Files"
        case .other: return "Other"
        }
    }

    static func category(for format: ParadoxFileFormat, fileName: String) -> ParadoxBrowserCategory {
        switch format {
        case .paradoxTable:
            return .tables
        case .paradoxQuery:
            return .queries
        case .paradoxReport:
            return .reports
        case .paradoxForm:
            return .forms
        case .paradoxFamily:
            return .families
        case .paradoxIndexPrimary, .paradoxIndexSecondary, .paradoxSecondaryIndexData:
            return .indexes
        case .paradoxScript:
            return .scripts
        case .calsRaster, .spicerSmf:
            return .images
        case .spreadsheet, .snapshot:
            return .supporting
        case .unknown:
            let lowered = fileName.lowercased()
            if lowered.contains("smf") || lowered.contains("cals") {
                return .images
            }
            return .other
        }
    }
}
