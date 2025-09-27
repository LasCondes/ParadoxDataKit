import Foundation
import ParadoxDataKit

struct ParadoxDirectoryScanner {
    func scan(directory url: URL) async throws -> [ParadoxBrowserCategory: [ParadoxScannedFile]] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw ScannerError.unableToEnumerate(url.path)
        }

        var fileURLs: [URL] = []
        while let next = enumerator.nextObject() as? URL {
            fileURLs.append(next)
        }
        let batches = fileURLs.chunked(into: 32)

        let grouped = await withTaskGroup(of: [ParadoxBrowserCategory: [ParadoxScannedFile]].self) { group in
            for batch in batches {
                group.addTask {
                    var localGroups: [ParadoxBrowserCategory: [ParadoxScannedFile]] = [:]
                    for fileURL in batch {
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                            guard resourceValues.isRegularFile == true else { continue }

                            let format = ParadoxFileFormat.infer(from: fileURL)
                            guard format != .unknown else { continue }

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
                            let category = ParadoxBrowserCategory.category(for: format, fileName: entry.name)
                            localGroups[category, default: []].append(entry)
                        } catch {
                            continue
                        }
                    }
                    return localGroups
                }
            }

            var aggregated: [ParadoxBrowserCategory: [ParadoxScannedFile]] = [:]
            for await batchGroups in group {
                for (category, entries) in batchGroups {
                    aggregated[category, default: []].append(contentsOf: entries)
                }
            }
            return aggregated
        }

        var filled: [ParadoxBrowserCategory: [ParadoxScannedFile]] = grouped
        for category in ParadoxBrowserCategory.allCases where filled[category] == nil {
            filled[category] = []
        }

        return filled
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
        switch format {
        case .paradoxIndexPrimary:
            return "Primary index structure"
        case .paradoxIndexSecondary:
            return "Secondary index structure"
        default:
            break
        }

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
            case .paradoxFamily(let family):
                if let firstTable = family.referencedFiles.first(where: { $0.kind == .table }) {
                    return "Family manifest for \(firstTable.name)"
                }
                return "Family manifest (\(family.referencedFiles.count) references)"
            case .paradoxIndex(let index):
                return "Index • Levels: \(index.header.levelCount) • Blocks: \(index.totalBlocksReported)"
            case .paradoxSecondaryIndexData(let indexData):
                return "Secondary index data • Fields: \(indexData.table.fields.count)"
            case .calsRaster(let raster):
                return "CALS image \(raster.widthPixels)x\(raster.heightPixels) @ \(raster.dpi) dpi"
            case .spicerSmf(let container):
                let raster = container.rasterDocument
                return "SMF (CALS \(raster.widthPixels)x\(raster.heightPixels))"
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

extension ParadoxScannedFile: @unchecked Sendable {}

enum ScannerError: Error, LocalizedError {
    case unableToEnumerate(String)

    var errorDescription: String? {
        switch self {
        case .unableToEnumerate(let path):
            return "Unable to enumerate directory at \(path)."
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count / size) + 1)
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}
