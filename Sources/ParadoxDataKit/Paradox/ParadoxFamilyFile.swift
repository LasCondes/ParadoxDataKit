import Foundation

/// Parsed representation of a Paradox family (`.FAM`) file.
///
/// Family files act as lightweight manifests that list every auxiliary file
/// associated with a Paradox application table set. The format is loosely
/// structured text, so this parser focuses on extracting human-readable
/// references while keeping the raw contents available for inspection.
public struct ParadoxFamilyFile {
    /// A referenced file discovered within the manifest.
    public struct ReferencedFile: Identifiable, Hashable {
        public enum Kind: String, CaseIterable, Sendable {
            case table = "Table"
            case primaryIndex = "Primary Index"
            case secondaryIndex = "Secondary Index"
            case memo = "Memo/Blob"
            case validity = "Validity"
            case query = "Query"
            case tableView = "Table View"
            case report = "Report"
            case script = "Script"
            case family = "Family"
            case image = "Image"
            case other = "Other"

            fileprivate static func kind(for fileExtension: String) -> Kind {
                let ext = fileExtension.lowercased()
                switch ext {
                case "db": return .table
                case "px": return .primaryIndex
                case "mb": return .memo
                case "val": return .validity
                case "qbe": return .query
                case "tv": return .tableView
                case "rsl": return .report
                case "ssl", "sdl": return .script
                case "fam": return .family
                case "clf", "cal", "cals", "smf": return .image
                default:
                    if ext.count == 3, let first = ext.first, ["x", "y"].contains(first) {
                        return .secondaryIndex
                    }
                    return .other
                }
            }
        }

        public let id: String
        public let name: String
        public let kind: Kind
        public let lineNumber: Int
        public let context: String

        init(name: String, kind: Kind, lineNumber: Int, context: String) {
            self.name = name
            self.kind = kind
            self.lineNumber = lineNumber
            self.context = context.trimmingCharacters(in: .whitespacesAndNewlines)
            self.id = "\(lineNumber)|\(name.lowercased())"
        }
    }

    /// The decoded textual contents of the manifest.
    public let text: String
    /// References to auxiliary files discovered in the manifest.
    public let referencedFiles: [ReferencedFile]

    public init(data: Data) {
        self.text = ParadoxFamilyFile.decodeText(from: data)
        self.referencedFiles = ParadoxFamilyFile.extractReferences(from: text)
    }

    private static func decodeText(from data: Data) -> String {
        let sanitized = Data(data.map { byte -> UInt8 in
            switch byte {
            case 0x00:
                return 0x0A // treat embedded NULs as line breaks
            case 0x09, 0x0A, 0x0D, 0x20...0x7E, 0x80...0xFF:
                return byte
            default:
                return 0x20
            }
        })

        if let cp1252 = String(data: sanitized, encoding: .windowsCP1252) {
            return cp1252
        }
        return String(decoding: sanitized, as: UTF8.self)
    }

    private static func extractReferences(from text: String) -> [ReferencedFile] {
        guard !text.isEmpty else { return [] }

        let pattern = #"(?i)([A-Z0-9_\-]+\.[A-Z0-9]{1,4})"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        var results: [ReferencedFile] = []
        var seen = Set<String>()

        let lines = text.components(separatedBy: CharacterSet.newlines)
        for (index, line) in lines.enumerated() {
            guard let regex else { break }
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                guard match.numberOfRanges >= 2,
                      let range = Range(match.range(at: 1), in: line) else { continue }
                let token = String(line[range])
                let normalized = token.uppercased()
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)

                let ext = normalized.split(separator: ".").last.map(String.init) ?? ""
                let kind = ReferencedFile.Kind.kind(for: ext)
                let reference = ReferencedFile(name: token, kind: kind, lineNumber: index + 1, context: line)
                results.append(reference)
            }
        }

        return results
    }
}
