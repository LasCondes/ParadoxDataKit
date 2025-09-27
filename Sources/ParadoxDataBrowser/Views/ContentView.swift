#if os(macOS)
import SwiftUI
import Combine
import ParadoxDataKit

struct ContentView: View {
    @StateObject private var viewModel = DirectoryBrowserViewModel()

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
                    Section(header: Text(category.displayName)) {
                        let files = viewModel.files(in: category)
                        if files.isEmpty {
                            Text("No files found")
                                .foregroundStyle(.secondary)
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
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
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
                ParadoxTableDetailView(table: table)
            case .paradoxQuery(let query):
                QueryDetailView(query: query)
            case .paradoxTableView(let view):
                TableViewDetailView(tableView: view)
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
    private let sampleLimit = 40

    private var headers: [String] {
        table.fieldDisplayNames()
    }

    private var rows: [[String]] {
        table.formattedRecords(sampleCount: sampleLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fields: \(table.fields.count) • Records loaded: \(table.records.count)")
                .font(.headline)

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
                Text("Field Definitions")
                    .font(.title3.bold())
                ForEach(Array(table.fields.enumerated()), id: \.0) { index, field in
                    Text("\(index + 1). \(field.name ?? "<unnamed>") — \(field.typeDescription) (\(field.length) bytes)")
                        .font(.subheadline)
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
    }

    private var recordGrid: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    ForEach(Array(headers.enumerated()), id: \.0) { _, header in
                        Text(header)
                            .font(.caption.bold())
                            .frame(minWidth: 130, alignment: .leading)
                            .padding(6)
                            .background(Color.accentColor.opacity(0.15))
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.0) { rowIndex, row in
                    HStack(spacing: 1) {
                        ForEach(Array(row.enumerated()), id: \.0) { _, value in
                            Text(value.isEmpty ? "—" : value)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minWidth: 130, alignment: .leading)
                                .padding(6)
                                .background(rowIndex.isMultiple(of: 2) ? Color.gray.opacity(0.08) : Color.clear)
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
    }
}

private struct QueryDetailView: View {
    let query: ParadoxQuery

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
            Text(query.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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
#endif
