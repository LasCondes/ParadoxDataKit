# ParadoxDataKit

ParadoxDataKit is a Swift package for exploring legacy Borland Paradox data on Apple platforms. It parses tables, queries, index structures, and memo blobs, exposing the results as strongly typed Swift models. A companion macOS app (ParadoxDataBrowser) lets you browse directories of Paradox files and generate SwiftData scaffolding.

## Features

- Parse Paradox `.DB` tables (including memo/graphic blobs stored in matching `.MB` files)
- Decode individual rows into strongly typed Swift `Decodable` models with `ParadoxDecoder`
- Load Paradox `.QBE` queries and `.TV` table-view layouts
- Decode primary index files (`.PX`) and secondary index pairs (`.Xnn` data tables + `.Ynn` B-trees)
- Extract metadata (record counts, field definitions, code pages, etc.)
- Generate SwiftData `@Model` skeletons with primary-key fields annotated as unique
- macOS sample browser with parallel directory scanning and key-field highlighting

## Requirements

- Swift 6.2+
- macOS 13+ (browser target)

## Installation

Add ParadoxDataKit to your `Package.swift`:

```swift
.package(url: "https://github.com/<your-org>/ParadoxDataKit.git", from: "1.0.0")
```

Then include the library in your target dependencies:

```swift
.target(
    name: "YourTool",
    dependencies: [
        .product(name: "ParadoxDataKit", package: "ParadoxDataKit")
    ]
)
```

## Usage Example

```swift
import ParadoxDataKit

let url = URL(fileURLWithPath: "/path/to/CUSTMAST.DB")
let file = try ParadoxFileReader.load(from: url)

if case .paradoxTable(let table) = file.details {
    print("Fields:\t", table.fields.count)
    print("Records:\t", table.records.count)
    for record in table.records.prefix(5) {
        print(record.formattedValues().joined(separator: " | "))
    }
}
```

## Supported File Types

| Extension | Purpose | Notes |
|-----------|---------|-------|
| `.db` | Table data | Companion `.mb` files store memo/graphic blobs. |
| `.mb` | Memo/blob store | Loaded automatically when tables reference it. |
| `.px` | Primary index B-tree | Parsed into block summaries and sample keys. |
| `.xnn` | Secondary index data table | Contains secondary key + primary key + hint columns. |
| `.ynn` | Secondary index B-tree | Parsed the same way as `.px`. |
| `.qbe` | Query definition | Text displayed in the browser. |
| `.tv` | Table view layout | Header metadata and string references extracted. |
| `.fam` | Family manifest | Lists related tables/indexes. |
| other | Raw binary | Exposed as `GenericBinaryFile` for inspection. |

## Decoding Records with `Decodable`

`ParadoxDecoder` turns a `ParadoxRecord` into any Swift `Decodable` type. Provide a `CodingKeys` enum that conforms to `ParadoxCodingKey` (and optionally `CaseIterable` for convenience helpers) and map each case to the canonical Paradox column name:

```swift
struct CustmastRow: Decodable {
    let customerId: Double
    let name: String?
    let status: String?

    private enum CodingKeys: String, CodingKey, ParadoxCodingKey, CaseIterable {
        case customerId = "CUSTOMERID"
        case name = "CUSTOMERNAME"
        case status = "STATUSCODE"
    }
}

let rows: [CustmastRow] = table.records.compactMap { record in
    try? ParadoxDecoder.decode(CustmastRow.self, from: record)
}
```

If a column appears under multiple aliases across databases, override `aliases` for that key:

```swift
private enum CodingKeys: String, CodingKey, ParadoxCodingKey, CaseIterable {
    case customerId = "CUSTOMERID"
    var aliases: [String] { ["CUSTOMERID", "CUSTID", "CUSTOMERNUMBER"] }
}
```

The helper extension `ParadoxCodingKey+FieldNames` (used in the sample app) illustrates how to gather all normalized aliases via `FieldSnapshot.normalizeKey`.

## Working with `FieldSnapshot`

For ad-hoc inspection you can build a `FieldSnapshot` directly. It normalises field names and converts `ParadoxValue` payloads into idiomatic Swift types:

```swift
let snapshot = FieldSnapshot(record: record)
let customerId = snapshot.identifier(for: ["CUSTOMERID"])
let createdOn = snapshot.date(for: ["DATEOFFIRSTCONTACT"])
let addressLines = snapshot.addressLines()
```

Utility methods such as `FieldSnapshot.trimmedOrNil(_:)` are public, so you can reuse the same whitespace handling outside of the decoder.

## SwiftData Model Generation

`SwiftDataModelRenderer` converts a `ParadoxTable` into a SwiftData `@Model` class:

```swift
let file = try ParadoxFileReader.load(from: tableURL)
if case .paradoxTable(let table) = file.details {
    let source = SwiftDataModelRenderer.renderModel(for: table, fallbackFileName: tableURL.lastPathComponent)
    print(source)
}
```

Generated models:
- Use the declared table name, or the file name when the table name is missing
- Annotate Paradox primary-key fields with `@Attribute(.unique)`
- Leave other properties optional because Paradox headers do not expose nullability

## ParadoxDataBrowser Highlights

The sample macOS app offers:

- Parallel directory scanning using Swift concurrency
- Schema and grid highlighting for primary-key columns
- Detail panes for `.PX` / `.Ynn` index structures and `.Xnn` data tables
- One-click SwiftData model generation from any table
- Copy/export actions for queries, manifests, and raw binaries

## Building & Testing

SwiftPM normally writes module caches under `~/Library`, which may be blocked in restricted environments. Use the helper scripts to keep caches inside the repository:

```bash
./Scripts/build.sh   # swift build with local module cache
./Scripts/test.sh    # swift test with local module cache
```

Both scripts create `.swiftpm/modulecache/` (if needed) and forward any additional arguments to the underlying `swift` command.

## Further Reading

- [teverett/paradoxReader](https://github.com/teverett/paradoxReader) – Community documentation of Paradox file formats

## Contributing

Bug reports and pull requests are welcome. When filing issues, please include sample Paradox files (with sensitive data removed) so we can reproduce and add regression tests.

## License

ParadoxDataKit is released under the MIT License. See [LICENSE](LICENSE) for details.
