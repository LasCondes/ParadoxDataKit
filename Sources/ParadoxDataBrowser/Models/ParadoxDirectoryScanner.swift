import Foundation
import ParadoxDataKit

struct ParadoxDirectoryScanner {
    func scan(directory url: URL) throws -> [ParadoxBrowserCategory: [ParadoxScannedFile]] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw ScannerError.unableToEnumerate(url.path)
        }

        var grouped: [ParadoxBrowserCategory: [ParadoxScannedFile]] = [:]
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { continue }

            let format = ParadoxFileFormat.infer(from: fileURL)
            guard format != .unknown else { continue }

            let fileName = fileURL.lastPathComponent.lowercased()
            let category = ParadoxBrowserCategory.category(for: fileName)

            let loadedFile: ParadoxFile?
            let errorMessage: String?

            do {
                loadedFile = try ParadoxFileReader.load(from: fileURL)
                errorMessage = nil
            } catch {
                loadedFile = nil
                errorMessage = error.localizedDescription
            }

            let entry = ParadoxScannedFile(
                url: fileURL,
                format: format,
                size: resourceValues.fileSize ?? loadedFile?.size ?? 0,
                loadedFile: loadedFile,
                errorMessage: errorMessage
            )

            grouped[category, default: []].append(entry)
        }

        for category in ParadoxBrowserCategory.allCases where grouped[category] == nil {
            grouped[category] = []
        }

        return grouped
    }
}

struct ParadoxScannedFile: Identifiable, Equatable {
    typealias ID = String

    let url: URL
    let format: ParadoxFileFormat
    let size: Int
    let loadedFile: ParadoxFile?
    let errorMessage: String?

    var id: ID { url.path }
    var name: String { url.lastPathComponent }

    var summary: String {
        if let errorMessage {
            return "Failed to load: \(errorMessage)"
        }
        if let loadedFile {
            switch loadedFile.details {
            case .paradoxTable(let table):
                return "Records: \(table.records.count), Fields: \(table.fields.count)"
            case .paradoxQuery:
                return "Query text (\(loadedFile.size) bytes)"
            case .paradoxTableView(let view):
                if let resolved = view.resolvedTableReference {
                    return "Table view referencing \(resolved)"
                }
                return "Table view metadata"
            case .binary:
                return "Binary data (\(loadedFile.size) bytes)"
            }
        }
        return "Unknown file"
    }

    static func == (lhs: ParadoxScannedFile, rhs: ParadoxScannedFile) -> Bool {
        lhs.url == rhs.url
    }
}

enum ScannerError: Error, LocalizedError {
    case unableToEnumerate(String)

    var errorDescription: String? {
        switch self {
        case .unableToEnumerate(let path):
            return "Unable to enumerate directory at \(path)."
        }
    }
}
