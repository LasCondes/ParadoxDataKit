#if os(macOS)
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import ParadoxDataKit

struct ContentView: View {
    @StateObject private var viewModel = DirectoryBrowserViewModel()
    @State private var collapsedCategories: Set<ParadoxBrowserCategory.ID> = []
    @FocusState private var isSidebarFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .frame(minWidth: 1000, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Choose Directory") {
                    viewModel.presentDirectoryPicker()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: viewModel.refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(viewModel.directoryURL == nil || viewModel.isLoading)
            }
        }
        .overlay(alignment: .center) {
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .padding()
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { isPresented in
            if !isPresented { viewModel.errorMessage = nil }
        })) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let path = viewModel.directoryURL?.path {
                Text(path)
                    .font(.headline)
                    .lineLimit(2)
                    .padding(.horizontal)
            } else {
                Text("Select a Paradox data directory to begin")
                    .font(.headline)
                    .padding(.horizontal)
            }

            List(selection: $viewModel.selectedFileID) {
                ForEach(viewModel.orderedCategories, id: \.id) { category in
                    DisclosureGroup(isExpanded: binding(for: category)) {
                        let files = viewModel.files(in: category)
                        if files.isEmpty {
                            Text("No files found")
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        } else {
                            ForEach(files) { file in
                                NavigationLink(value: file.id) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.name)
                                            .font(.headline)
                                        Text(file.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.leading, 4)
                            }
                        }
                    } label: {
                        Text(category.displayName)
                            .font(.headline)
                    }
                }
            }
            .listStyle(.sidebar)
            .focused($isSidebarFocused)
            .onAppear { isSidebarFocused = true }
            .onTapGesture { isSidebarFocused = true }
            .onMoveCommand(perform: handleMove)
        }
    }

    private func binding(for category: ParadoxBrowserCategory) -> Binding<Bool> {
        Binding(
            get: { !collapsedCategories.contains(category.id) },
            set: { isExpanded in
                if isExpanded {
                    collapsedCategories.remove(category.id)
                } else {
                    collapsedCategories.insert(category.id)
                }
            }
        )
    }

    private var visibleFileIDs: [ParadoxScannedFile.ID] {
        viewModel.orderedCategories.reduce(into: []) { result, category in
            guard !collapsedCategories.contains(category.id) else { return }
            result.append(contentsOf: viewModel.files(in: category).map(\.id))
        }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        let ids = visibleFileIDs
        guard !ids.isEmpty else { return }

        let currentIndex = viewModel.selectedFileID.flatMap { ids.firstIndex(of: $0) }

        switch direction {
        case .up:
            let newIndex = currentIndex.map { max($0 - 1, 0) } ?? ids.count - 1
            viewModel.selectedFileID = ids[newIndex]
        case .down:
            let newIndex = currentIndex.map { min($0 + 1, ids.count - 1) } ?? 0
            viewModel.selectedFileID = ids[newIndex]
        default:
            break
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedID = viewModel.selectedFileID, let file = viewModel.file(for: selectedID) {
            FileDetailView(file: file)
        } else if viewModel.directoryURL == nil {
            VStack(spacing: 16) {
                Image(systemName: "folder")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Choose a directory to explore Paradox files.")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Select a file to see details.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FileDetailView: View {
    let file: ParadoxScannedFile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
                if let error = file.errorMessage {
                    Text("Error loading file: \(error)")
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle(file.name)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.url.lastPathComponent)
                .font(.title2.bold())
            Text(file.url.path)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Format: \(file.format.description) • Size: \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loaded = file.loadedFile {
            switch loaded.details {
            case .paradoxTable(let table):
                ParadoxTableDetailView(table: table, sourceFileName: file.url.lastPathComponent)
            case .paradoxQuery(let query):
                QueryDetailView(query: query)
            case .paradoxTableView(let view):
                TableViewDetailView(tableView: view)
            case .paradoxFamily(let family):
                ParadoxFamilyDetailView(family: family)
            case .paradoxSecondaryIndexData(let indexData):
                ParadoxSecondaryIndexDataDetailView(indexData: indexData)
            case .paradoxIndex(let index):
                ParadoxIndexDetailView(index: index)
            case .calsRaster(let raster):
                CalsRasterDetailView(document: raster)
            case .spicerSmf(let container):
                SpicerSmfDetailView(document: container)
            case .binary(let binary):
                BinaryPreviewView(binary: binary)
            }
        } else {
            Text("Preview unavailable")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ParadoxTableDetailView: View {
    let table: ParadoxTable
    let sourceFileName: String?
    private let sampleLimit = 40
    @State private var modelSheetPayload: SwiftDataModelSheet?

    init(table: ParadoxTable, sourceFileName: String? = nil) {
        self.table = table
        self.sourceFileName = sourceFileName
    }

    private struct SwiftDataModelSheet: Identifiable {
        let id = UUID()
        let source: String
        let suggestedFileName: String
    }

    private var headerMetadata: [(title: String, value: String)] {
        let header = table.header
        var entries: [(String, String)] = []

        if let fileType = header.fileType {
            entries.append(("File Type", fileType.summary))
        } else {
            entries.append(("File Type", String(format: "Unknown (0x%02X)", header.fileTypeRaw)))
        }

        if header.normalizedFileVersion > 0 {
            entries.append(("Version", "Paradox \(header.normalizedFileVersion / 10).\(header.normalizedFileVersion % 10)"))
        }

        entries.append(("Record Size", "\(header.recordSize) bytes"))
        entries.append(("Header Length", "\(header.headerLengthInBytes) bytes"))
        entries.append(("Data Block Size", "\(header.dataBlockSize) bytes"))
        entries.append(("Rows Declared", "\(header.rowCount)"))
        entries.append(("Fields Declared", "\(header.fieldCount)"))

        if header.keyFieldCount > 0 {
            entries.append(("Key Fields", "\(header.keyFieldCount)"))
        }

        if header.autoIncrementValue != 0 {
            entries.append(("Auto Increment Next", "\(header.autoIncrementValue)"))
        }

        entries.append(("Field Info Offset", String(format: "0x%02X", header.fieldInfoOffset)))
        entries.append(("Includes Data Header", header.includesDataHeader ? "Yes" : "No"))

        return entries
    }

    private var headers: [String] {
        table.fieldDisplayNames()
    }

    private var rows: [[String]] {
        table.formattedRecords(sampleCount: sampleLimit)
    }

    private var keyFieldCount: Int {
        Int(table.header.keyFieldCount)
    }

    private var columnWidths: [CGFloat] {
        guard !headers.isEmpty else { return [] }

        let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let minWidth: CGFloat = 110
        let maxWidth: CGFloat = 260
        let paddingAllowance: CGFloat = 12

        func measuredWidth(for text: String, font: NSFont) -> CGFloat {
            guard !text.isEmpty else { return minWidth }
            let string = text as NSString
            let size = string.size(withAttributes: [.font: font])
            return ceil(size.width)
        }

        var widths = Array(repeating: minWidth, count: headers.count)

        for (index, header) in headers.enumerated() {
            let width = measuredWidth(for: header, font: headerFont) + paddingAllowance
            widths[index] = max(widths[index], width)
        }

        for row in rows {
            for (index, value) in row.enumerated() where index < widths.count {
                let displayValue = value.isEmpty ? "—" : value
                let width = measuredWidth(for: displayValue, font: valueFont) + paddingAllowance
                widths[index] = max(widths[index], width)
            }
        }

        return widths.map { min(max($0, minWidth), maxWidth) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fields: \(table.fields.count) • Records loaded: \(table.records.count)")
                .font(.headline)

            Button {
                let modelName = SwiftDataModelRenderer.defaultModelName(for: table, fallbackFileName: sourceFileName)
                let source = SwiftDataModelRenderer.renderModel(for: table, modelName: modelName, fallbackFileName: sourceFileName)
                modelSheetPayload = SwiftDataModelSheet(
                    source: source,
                    suggestedFileName: "\(modelName).swift"
                )
            } label: {
                Label("Generate SwiftData Model", systemImage: "doc.badge.gearshape")
            }
            .buttonStyle(.borderedProminent)

            if let name = table.tableName, !name.isEmpty {
                Text("Table Name: \(name)")
                    .font(.subheadline)
            }
            if let sort = table.sortOrder, !sort.isEmpty {
                Text("Sort Order: \(sort)")
                    .font(.subheadline)
            }
            if let codePage = table.codePageIdentifier {
                Text(String(format: "Code Page: 0x%04X", codePage))
                    .font(.subheadline)
            }
            if let seed = table.autoIncrementSeed {
                Text("Auto Increment Seed: \(seed)")
                    .font(.subheadline)
            }

            if table.fields.isEmpty {
                Text("This table does not define any fields.")
                    .foregroundStyle(.secondary)
            } else {
                if !headerMetadata.isEmpty {
                    Text("Header Metadata")
                        .font(.title3.bold())
                        .padding(.top, 4)
                    ForEach(Array(headerMetadata.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(entry.title + ":")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 160, alignment: .leading)
                            Text(entry.value)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider()
                        .padding(.vertical, 8)
                }

                Text("Field Definitions")
                    .font(.title3.bold())
                ForEach(Array(table.fields.enumerated()), id: \.0) { index, field in
                    let isKey = index < table.header.keyFieldCount
                    Text("\(index + 1). \(field.name ?? "<unnamed>") — \(field.typeDescription) (\(field.length) bytes)\(isKey ? " [Primary Key]" : "")")
                        .font(.subheadline)
                        .fontWeight(isKey ? .semibold : .regular)
                        .foregroundStyle(isKey ? Color.accentColor : Color.primary)
                }
            }

            Divider()
                .padding(.vertical, 8)

            Text("Sample Records")
                .font(.title3.bold())

            if table.records.isEmpty {
                Text("No records available.")
                    .foregroundStyle(.secondary)
            } else {
                recordGrid
            }
        }
        .sheet(item: $modelSheetPayload) { payload in
            SwiftDataModelExportView(source: payload.source, suggestedFileName: payload.suggestedFileName)
        }
    }

    private var recordGrid: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    ForEach(Array(headers.enumerated()), id: \.0) { index, header in
                        let isPrimaryKey = index < keyFieldCount
                        Text(header)
                            .font(.caption.bold())
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: index < columnWidths.count ? columnWidths[index] : 130, alignment: .leading)
                            .padding(6)
                            .background(isPrimaryKey ? Color.accentColor.opacity(0.65) : Color.accentColor.opacity(0.15))
                            .foregroundStyle(isPrimaryKey ? Color.white : Color.primary)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.0) { rowIndex, row in
                    HStack(spacing: 1) {
                        ForEach(Array(row.enumerated()), id: \.0) { index, value in
                            let isPrimaryKey = index < keyFieldCount
                            Text(value.isEmpty ? "—" : value)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: index < columnWidths.count ? columnWidths[index] : 130, alignment: .leading)
                                .padding(6)
                                .background(isPrimaryKey
                                    ? (rowIndex.isMultiple(of: 2) ? Color.accentColor.opacity(0.20) : Color.accentColor.opacity(0.12))
                                    : (rowIndex.isMultiple(of: 2) ? Color.gray.opacity(0.08) : Color.clear)
                                )
                                .foregroundStyle(isPrimaryKey ? Color.primary : Color.primary)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .frame(maxHeight: 360)
        .textSelection(.enabled)
    }
}

private struct ParadoxFamilyDetailView: View {
    let family: ParadoxFamilyFile

    private struct GroupedReferences: Identifiable {
        let kind: ParadoxFamilyFile.ReferencedFile.Kind
        let files: [ParadoxFamilyFile.ReferencedFile]

        var id: ParadoxFamilyFile.ReferencedFile.Kind { kind }
    }

    private var groupedReferences: [GroupedReferences] {
        guard !family.referencedFiles.isEmpty else { return [] }
        let groups = Dictionary(grouping: family.referencedFiles, by: \.kind)
        let ordered = ParadoxFamilyFile.ReferencedFile.Kind.allCases.compactMap { kind -> GroupedReferences? in
            guard let files = groups[kind] else { return nil }
            let sorted = files.sorted { lhs, rhs in
                if lhs.lineNumber == rhs.lineNumber {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.lineNumber < rhs.lineNumber
            }
            return GroupedReferences(kind: kind, files: sorted)
        }
        return ordered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if groupedReferences.isEmpty {
                Text("No referenced files were detected in this family manifest.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedReferences) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.kind.rawValue)
                            .font(.headline)
                        ForEach(group.files) { reference in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reference.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("Line \(reference.lineNumber): \(reference.context)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }

            DisclosureGroup("Raw Manifest Text") {
                ScrollView {
                    Text(family.text.isEmpty ? "<empty>" : family.text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 240)
            }
        }
    }
}

private struct QueryDetailView: View {
    let query: ParadoxQuery
    @State private var copyConfirmation: Bool = false

    private var encodingName: String {
        if query.encodingUsed == .windowsCP1252 {
            return "Windows CP1252"
        } else if query.encodingUsed == .ascii {
            return "ASCII"
        } else {
            return "Unknown"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Encoding: \(encodingName)")
                .font(.subheadline)
            Button {
                copyToClipboard(query.text)
                copyConfirmation = true
            } label: {
                Label("Copy Query Text", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            Text(query.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .overlay(alignment: .bottomTrailing) {
            if copyConfirmation {
                Text("Copied")
                    .font(.caption)
                    .padding(6)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { copyConfirmation = false }
                        }
                    }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct TableViewDetailView: View {
    let tableView: ParadoxTableView

    private var metadataEntries: [(title: String, value: String)] {
        var entries: [(String, String)] = []
        entries.append(("File Signature", tableView.signature))
        if let version = tableView.version {
            entries.append(("Version", String(version)))
        }
        if let flags = tableView.flags {
            entries.append(("Flags", String(format: "0x%04X", flags)))
        }
        if let length = tableView.declaredLength {
            entries.append(("Declared Length", ByteCountFormatter.string(fromByteCount: Int64(length), countStyle: .file)))
        }
        if let offset = tableView.firstBlockOffset {
            entries.append(("First Block Offset", String(format: "0x%04X", offset)))
        }
        if let directory = tableView.directoryHint, !directory.isEmpty {
            entries.append(("Directory Hint", directory))
        }
        if let table = tableView.tableFileName, !table.isEmpty {
            entries.append(("Table File", table))
        }
        if let resolved = tableView.resolvedTableReference, !resolved.isEmpty {
            entries.append(("Resolved Reference", resolved))
        }
        if !tableView.additionalStrings.isEmpty {
            for (index, value) in tableView.additionalStrings.enumerated() {
                entries.append(("Extra String \(index + 1)", value))
            }
        }
        entries.append(("Binary Size", ByteCountFormatter.string(fromByteCount: Int64(tableView.binary.size), countStyle: .file)))
        return entries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Table View Metadata")
                    .font(.title3.bold())
                ForEach(Array(metadataEntries.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.title + ":")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 170, alignment: .leading)
                        Text(entry.value)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Divider()

            BinaryPreviewView(binary: tableView.binary)
        }
    }
}

private struct CalsRasterDetailView: View {
    let document: CalsRasterDocument

    private var previewImage: NSImage? {
        NSImage(data: document.makeTiffData())
    }

    private var payloadDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(document.rawImageData.count), countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxHeight: 480)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text("Unable to render CALS raster preview.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Dimensions: \(document.widthPixels)x\(document.heightPixels) @ \(document.dpi) dpi")
                    .font(.headline)
                if !document.orientation.isEmpty {
                    Text("Orientation: \(document.orientation)")
                        .font(.subheadline)
                }
                Text("Payload size: \(payloadDescription)")
                    .font(.subheadline)
                Text("Header offset: \(document.headerOffset) bytes")
                    .font(.subheadline)
            }

            DisclosureGroup("Header records (\(document.headerRecords.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(document.headerRecords, id: \.self) { record in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(record.name)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            Text(record.value)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

private struct SpicerSmfDetailView: View {
    let document: SpicerSMFDocument

    private var headerDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(document.containerHeader.count), countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spicer SMF Container")
                    .font(.title3.bold())
                Text("Header bytes: \(document.containerHeader.count) (\(headerDescription))")
                    .font(.subheadline)
                if let signature = document.signature {
                    Text("Signature: \(signature)")
                        .font(.subheadline)
                }
            }

            Divider()

            CalsRasterDetailView(document: document.rasterDocument)
        }
    }
}

private struct BinaryPreviewView: View {
    private enum PreviewMode: String, CaseIterable, Identifiable {
        case text = "Text"
        case hex = "Hex"

        var id: String { rawValue }
    }

    private let binary: GenericBinaryFile
    private let asciiSegments: [GenericBinaryAsciiSegment]
    @State private var mode: PreviewMode
    private let hexPreviewLength = 64

    init(binary: GenericBinaryFile) {
        self.binary = binary
        let segments = binary.asciiSegments()
        self.asciiSegments = segments
        self._mode = State(initialValue: segments.isEmpty ? .hex : .text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Group {
                switch mode {
                case .text:
                    textPreview
                case .hex:
                    hexPreview
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Binary Preview")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Preview mode", selection: $mode) {
                ForEach(PreviewMode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .disabled(asciiSegments.isEmpty)
        }
    }

    private var subtitle: String {
        switch mode {
        case .hex:
            return "First \(hexPreviewLength) bytes (hex + ASCII)"
        case .text:
            return "Printable strings detected near file start"
        }
    }

    private var hexPreview: some View {
        Text(binary.hexDump(prefixLength: hexPreviewLength))
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if asciiSegments.isEmpty {
                Text("No printable ASCII sequences found in the first 512 bytes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(asciiSegments, id: \.self) { segment in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "0x%04X", segment.offset))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(segment.text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("Showing printable sequences within the first 512 bytes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SwiftDataModelExportView: View {
    @State private var text: String
    private let suggestedFileName: String
    @Environment(\.dismiss) private var dismiss

    init(source: String, suggestedFileName: String) {
        _text = State(initialValue: source)
        self.suggestedFileName = suggestedFileName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    copyToClipboard(text)
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                Button {
                    saveToFile(text)
                } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 520, minHeight: 360)
                .border(Color.gray.opacity(0.3), width: 1)
        }
        .padding()
    }

    private func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func saveToFile(_ string: String) {
        let panel = NSSavePanel()
        if #available(macOS 13.0, *) {
            panel.allowedContentTypes = [.swiftSource]
        } else {
            panel.allowedFileTypes = ["swift"]
        }
        panel.nameFieldStringValue = suggestedFileName
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try string.data(using: .utf8)?.write(to: url)
            } catch {
                NSSound.beep()
            }
        }
    }
}

private struct ParadoxIndexDetailView: View {
    let index: ParadoxIndex

    private var metadataEntries: [(String, String)] {
        let header = index.header
        var entries: [(String, String)] = []
        entries.append(("Kind", index.kind == .primary ? "Primary" : "Secondary"))
        entries.append(("Record Length", "\(header.recordLength) bytes"))
        entries.append(("Header Length", "\(header.headerLength) bytes"))
        entries.append(("Block Size", "\(header.blockSize) bytes"))
        entries.append(("Index Levels", "\(header.levelCount)"))
        entries.append(("Fields", "\(header.fieldCount)"))
        entries.append(("Records Declared", "\(header.recordCount)"))
        entries.append(("Blocks In Use", "\(header.blocksInUse)"))
        entries.append(("Total Blocks", "\(header.totalBlocks)"))
        entries.append(("Root Block", "\(header.rootBlockNumber)"))
        entries.append(("First Data Block", "\(header.firstDataBlock)"))
        entries.append(("Last Block", "\(header.lastBlockInUse)"))
        return entries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                blockSection
            }
            .padding()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Index Metadata")
                .font(.title3.bold())
            ForEach(metadataEntries, id: \.0) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.0 + ":")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 180, alignment: .leading)
                    Text(entry.1)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var blockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Block Overview")
                .font(.title3.bold())
            let hiddenBlockCount = max(0, index.totalBlocksReported - index.blocks.count)
            if hiddenBlockCount > 0 {
                Text("Showing first \(index.blocks.count) blocks (\(hiddenBlockCount) more not displayed).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if index.blocks.isEmpty {
                Text("No index blocks detected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(index.blocks) { block in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Block #\(block.id)")
                                .font(.headline)
                            Spacer()
                            Text("Records: \(block.recordCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 16) {
                            Text("Next: \(block.nextBlock)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Previous: \(block.previousBlock)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if block.records.isEmpty {
                            Text("<empty block>")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(block.records) { record in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Key: \(record.keyHex)")
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                        HStack(spacing: 16) {
                                            Text("Child Block: \(record.childBlockNumber)")
                                            Text("Statistics: \(record.statistics)")
                                            if record.reserved != 0 {
                                                Text("Reserved: \(record.reserved)")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(6)
                                    .background(Color.gray.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct ParadoxSecondaryIndexDataDetailView: View {
    let indexData: ParadoxSecondaryIndexData

    private var table: ParadoxTable { indexData.table }
    private let sampleLimit = 32

    private var headers: [String] {
        table.fieldDisplayNames()
    }

    private var rows: [[String]] {
        table.formattedRecords(sampleCount: sampleLimit)
    }

    private var keyFieldCount: Int {
        Int(table.header.keyFieldCount)
    }

    private var columnWidths: [CGFloat] {
        guard !headers.isEmpty else { return [] }

        let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let minWidth: CGFloat = 110
        let maxWidth: CGFloat = 260
        let paddingAllowance: CGFloat = 12

        func measuredWidth(for text: String, font: NSFont) -> CGFloat {
            guard !text.isEmpty else { return minWidth }
            let string = text as NSString
            let size = string.size(withAttributes: [.font: font])
            return ceil(size.width)
        }

        var widths = Array(repeating: minWidth, count: headers.count)

        for (index, header) in headers.enumerated() {
            let width = measuredWidth(for: header, font: headerFont) + paddingAllowance
            widths[index] = max(widths[index], width)
        }

        for row in rows {
            for (index, value) in row.enumerated() where index < widths.count {
                let displayValue = value.isEmpty ? "—" : value
                let width = measuredWidth(for: displayValue, font: valueFont) + paddingAllowance
                widths[index] = max(widths[index], width)
            }
        }

        return widths.map { min(max($0, minWidth), maxWidth) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Secondary Index Metadata")
                    .font(.title3.bold())
                Text("Total records: \(indexData.table.records.count)")
                    .font(.subheadline)
                Text("Key fields: \(indexData.table.header.keyFieldCount)")
                    .font(.subheadline)
                if let sortOrder = indexData.sortOrder {
                    Text("Sort order: \(sortOrder)")
                        .font(.subheadline)
                }
                if let label = indexData.indexLabel {
                    Text("Index label: \(label)")
                        .font(.subheadline)
                }
                if let hint = indexData.hintFieldName {
                    Text("Hint field: \(hint)")
                        .font(.subheadline)
                }
            }

            let keyFieldNames = indexData.keyFieldNames
            let inferredSecondaryCount = min(indexData.secondaryFieldReferences.count, keyFieldNames.count)
            let secondaryNames = Array(keyFieldNames.prefix(inferredSecondaryCount))
            let primaryContinuation = Array(keyFieldNames.dropFirst(inferredSecondaryCount))

            if !secondaryNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Secondary key fields")
                        .font(.headline)
                    ForEach(Array(secondaryNames.enumerated()), id: \.offset) { index, name in
                        Text("\(index + 1). \(name)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            if !primaryContinuation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Primary key continuation")
                        .font(.headline)
                    ForEach(Array(primaryContinuation.enumerated()), id: \.offset) { index, name in
                        Text("\(index + 1). \(name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !indexData.secondaryFieldReferences.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Field references to base table")
                        .font(.headline)
                    Text(indexData.secondaryFieldReferences.map { String($0) }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Sample Rows")
                .font(.headline)

            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 1) {
                        ForEach(Array(headers.enumerated()), id: \.0) { index, header in
                            let isPrimaryKey = index < keyFieldCount
                            Text(header)
                                .font(.caption.bold())
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: index < columnWidths.count ? columnWidths[index] : 130, alignment: .leading)
                                .padding(6)
                                .background(isPrimaryKey ? Color.accentColor.opacity(0.65) : Color.accentColor.opacity(0.15))
                                .foregroundStyle(isPrimaryKey ? Color.white : Color.primary)
                        }
                    }
                    ForEach(Array(rows.enumerated()), id: \.0) { rowIndex, row in
                        HStack(spacing: 1) {
                            ForEach(Array(row.enumerated()), id: \.0) { index, value in
                                let isPrimaryKey = index < keyFieldCount
                                Text(value.isEmpty ? "—" : value)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: index < columnWidths.count ? columnWidths[index] : 130, alignment: .leading)
                                    .padding(6)
                                    .background(isPrimaryKey
                                        ? (rowIndex.isMultiple(of: 2) ? Color.accentColor.opacity(0.20) : Color.accentColor.opacity(0.12))
                                        : (rowIndex.isMultiple(of: 2) ? Color.gray.opacity(0.08) : Color.clear)
                                    )
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .frame(maxHeight: 320)
            .textSelection(.enabled)
        }
    }
}
#endif
