#if os(macOS)
import Foundation
import ParadoxDataKit
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class DirectoryBrowserViewModel: ObservableObject {
    @Published var directoryURL: URL?
    @Published var groupedFiles: [ParadoxBrowserCategory: [ParadoxScannedFile]] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedFileID: ParadoxScannedFile.ID?

    private let scanner = ParadoxDirectoryScanner()
    private var fileMap: [ParadoxScannedFile.ID: ParadoxScannedFile] = [:]
    private var scanTask: Task<Void, Never>?

    var orderedCategories: [ParadoxBrowserCategory] {
        ParadoxBrowserCategory.allCases
    }

    func files(in category: ParadoxBrowserCategory) -> [ParadoxScannedFile] {
        let files = groupedFiles[category] ?? []
        return files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func file(for id: ParadoxScannedFile.ID) -> ParadoxScannedFile? {
        fileMap[id]
    }

    func loadDirectory(_ url: URL) {
        directoryURL = url
        errorMessage = nil
        isLoading = true
        groupedFiles = [:]
        fileMap = [:]
        selectedFileID = nil

        scanTask?.cancel()
        scanTask = Task(priority: .userInitiated) { [scanner] in
            do {
                let result = try scanner.scan(directory: url)
                await MainActor.run {
                    self.groupedFiles = result
                    self.rebuildFileMap(with: result)
                    self.isLoading = false
                    self.selectedFileID = self.firstAvailableSelection()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isLoading = false
    }

    func firstAvailableSelection() -> ParadoxScannedFile.ID? {
        for category in orderedCategories {
            if let first = files(in: category).first {
                return first.id
            }
        }
        return nil
    }

    func refresh() {
        guard let directoryURL else { return }
        loadDirectory(directoryURL)
    }

    #if canImport(AppKit)
    func presentDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            loadDirectory(url)
        }
    }
    #endif

    private func rebuildFileMap(with grouped: [ParadoxBrowserCategory: [ParadoxScannedFile]]) {
        var map: [ParadoxScannedFile.ID: ParadoxScannedFile] = [:]
        for (_, files) in grouped {
            for file in files {
                map[file.id] = file
            }
        }
        fileMap = map
    }
}
#endif
