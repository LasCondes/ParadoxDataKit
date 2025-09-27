# ParadoxDataKit

ParadoxDataKit is a Swift package for decoding legacy Borland Paradox data files on macOS.
It understands the family of Paradox artefacts (tables, queries, memo/blob stores) and
presents their contents as strongly-typed Swift models. It can be re-used
in any project that needs to inspect Paradox databases.

## Features

- Parse Paradox `.DB` tables, including memo/graphic fields stored in matching `.MB` files
- Inspect Paradox `.QBE` query files and raw binary assets (`.RSL`, `.TV`, etc.)
- Decode CALS raster images (`.CLF`) and Spicer `.SMF` containers with a one-call TIFF wrapper for previews
- Surface Paradox index metadata (`.PX`, `.Ynn`) and secondary index data tables (`.Xnn`)
- Generate SwiftData `@Model` boilerplate with primary-key fields annotated for uniqueness
- Enumerate header metadata: record size, file type, field definitions, code page, and more
- Decode records into typed `ParadoxValue` instances and generate formatted strings for UI
- Convenience hex dump for unsupported binary formats

## Requirements

- macOS 13 or newer
- Swift 6.2 or newer (tested with the Xcode 16 toolchain)

## Installation

Add ParadoxDataKit to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/<your-org>/ParadoxDataKit.git", from: "1.0.0")
```

Then add the library to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "ParadoxDataKit", package: "ParadoxDataKit")
    ]
)
```

ParadoxDataKit also ships an optional sample macOS app target (`ParadoxDataBrowser`) that
you can reference while developing to explore directories of Paradox files.

## Usage

```swift
import ParadoxDataKit

let fileURL = URL(fileURLWithPath: "path/to/Custmast.DB")
let parsedFile = try ParadoxFileReader.load(from: fileURL)

if case .paradoxTable(let table) = parsedFile.details {
    print(table.summary)
    for record in table.records.prefix(5) {
        let values = record.formattedValues()
        print(values.joined(separator: " | "))
    }
}
```

### Working with Queries

```swift
let queryURL = URL(fileURLWithPath: "path/to/report.QBE")
let query = try ParadoxFileReader.load(from: queryURL)
if case .paradoxQuery(let qbe) = query.details {
    print(qbe.text)
}
```

## Module Overview

- ``ParadoxFileReader`` – top-level loader that infers file type, exposes metadata, and
  resolves memo/blob references
- ``ParadoxFileFormat`` – enum describing known Paradox-related file extensions
- ``ParadoxTableView`` – exposes header metadata and references from Paradox `.TV` table-view files
- ``ParadoxFamilyFile`` – parses text manifests listing the related Paradox assets for a table family
- ``SwiftDataModelRenderer`` – generates SwiftData `@Model` declarations from Paradox table schemas
- ``CalsRasterDocument`` & ``SpicerSMFDocument`` – parse bitonal CALS pages and SMF wrappers
- ``ParadoxTable`` – parsed representation of a table including field descriptors and
  strongly-typed records
- ``ParadoxRecord`` & ``ParadoxValue`` – decode per-record values with formatters and
  helper accessors
- ``ParadoxQuery`` – wraps the text contents of Paradox QBE files
- ``GenericBinaryFile`` – fallback representation for unsupported binary assets

## Paradox File Types

| Extension | Purpose | Notes |
|-----------|---------|-------|
| `.db` | Table data | Companion `.mb` memo/graphic files store overflow text and images. |
| `.qbe` | Query (Query By Example) definition | Text-based, loaded into `ParadoxQuery`. |
| `.rsl` | Report layout | Currently exposed as raw binary. |
| `.fam` | Family manifest | Lists related tables, indexes, memo stores, queries, and views. |
| `.px` | Primary index | Lookup tree for the leading key in a table. |
| `.xnn` | Secondary index data tables | Store secondary key + primary key + hint for `.Ynn` trees. |
| `.ynn` | Secondary index B-tree | Parsed like `.PX`; points into matching `.Xnn` tables. |
| `.tv` | Table view layout | Stores Paradox UI preferences (column order, widths, captions). |
| `.clf` / `.cal` / `.cals` | CALS raster image | Rendered through `CalsRasterDocument`. |
| `.smf` | Spicer SMF container | Wraps CALS rasters; parsed by `SpicerSMFDocument`. |
| other | Unknown binary asset | Delivered via `GenericBinaryFile`. |

### About `.tv` files

Paradox creates a `.tv` file the first time you customize how a table should appear in the Windows UI.
These binaries:

- start with the `"Borland Standard File"` signature, followed by a short header containing version,
  flags, and offsets.
- embed null-terminated Windows-1252 strings for the directory hint, table filename, and up to four
  additional labels. `ParadoxTableView` surfaces these strings and keeps the remaining payload available
  as a `GenericBinaryFile` for further inspection.
- contain no data rows—only presentation metadata. If the file is missing, Paradox falls back to default
  column sizing and order when the table opens.

The binary layout beyond the exposed header is still undocumented by Borland/Corel. Contributions that
decode additional structures (field descriptors, control blocks, triggers) are very welcome.

## Generating SwiftData models

If you need to migrate Paradox tables into a modern SwiftData stack, use
``SwiftDataModelRenderer`` to emit starter `@Model` classes. The renderer walks the
``ParadoxTable`` schema, maps field types onto Swift primitives, and returns a Swift
source file you can paste into your project:

```swift
let file = try ParadoxFileReader.load(from: tableURL)
if case .paradoxTable(let table) = file.details {
    let swiftDataSource = SwiftDataModelRenderer.renderModel(for: table, modelName: "Customer")
    print(swiftDataSource)
}
```

Key fields are annotated with `@Attribute(.unique)` so you can spot the primary key.
Other properties default to optionals because Paradox tables expose no nullability
metadata. Review the output, adjust types, and add relationships that make sense for
your domain before compiling.

## ParadoxDataBrowser Highlights

The sample macOS app (`ParadoxDataBrowser`) is convenient when reverse engineering
legacy directories:

- Directory scanning runs in parallel so even large datasets enumerate quickly.
- Primary key columns are highlighted in sample-record grids, and key fields are
  flagged in the schema list.
- Secondary index data files (`.Xnn`) show secondary-key, primary-key, and hint
  columns alongside the underlying rows.
- Index trees (`.PX`, `.Ynn`) list block metadata so you can inspect the B-tree
  structure without leaving the app.
- Each table view provides a “Generate SwiftData Model” button that immediately emits
  Swift code using the file name when the Paradox header lacks a table name.

## Further Reading

- [teverett/paradoxReader](https://github.com/teverett/paradoxReader) – Java-based tooling and reference notes for Paradox file structures (DB, PX, MB, Xnn/Ynn). Helpful when cross-checking the binary layouts surfaced by ParadoxDataKit.

## Contributing

Bug reports and pull requests are welcome! Please include sample Paradox files (with any
sensitive data removed) when filing parsing issues so we can reproduce and add regression
tests.

## License

ParadoxDataKit is released under the MIT license. See [LICENSE](LICENSE) for details.
