import Foundation

/// Generates SwiftData `@Model` declarations from ``ParadoxTable`` metadata.
public enum SwiftDataModelRenderer {
    /// Renders a Swift source file containing a single `@Model` class that mirrors
    /// the supplied Paradox table schema.
    ///
    /// - Parameters:
    ///   - table: The parsed Paradox table to describe.
    ///   - modelName: Optional override for the generated model name. When `nil`,
    ///     the table name (without extension) is converted into a valid Swift type name.
    /// - Returns: Swift source code that you can drop into a SwiftData target.
    public static func renderModel(for table: ParadoxTable, modelName: String? = nil, fallbackFileName: String? = nil) -> String {
        let typeName = defaultModelName(for: table, override: modelName, fallbackFileName: fallbackFileName)
        var usedNames = Set<String>()
        let primaryKeyIndexes = Set(0..<Int(table.header.keyFieldCount))
        let fieldLines = table.fields.enumerated().map { index, descriptor in
            renderProperty(for: descriptor, index: index, isPrimaryKey: primaryKeyIndexes.contains(index), usedNames: &usedNames)
        }.joined(separator: "\n\n")

        let originalNameComment: String
        if let original = table.tableName, !original.isEmpty {
            originalNameComment = "// Paradox table: \(original)"
        } else if let fallbackFileName, !fallbackFileName.isEmpty {
            originalNameComment = "// Paradox table from file: \(fallbackFileName)"
        } else {
            originalNameComment = "// Paradox table without a declared name"
        }

        return [
            "import Foundation",
            "import SwiftData",
            "",
            originalNameComment,
            "@Model",
            "final class \(typeName) {",
            "    /// Synthetic identifier for SwiftData bookkeeping.",
            "    var id: UUID = UUID()",
            fieldLines.isEmpty ? "" : "\n\(fieldLines)" ,
            "",
            "    init() {}",
            "}",
            "",
            "extension \(typeName) {",
            "    static let paradoxFieldCount = \(table.fields.count)",
            "}"
        ].joined(separator: "\n")
    }

    /// Returns the sanitized name that ``renderModel(for:modelName:)`` uses for the SwiftData type.
    public static func defaultModelName(for table: ParadoxTable, override: String? = nil, fallbackFileName: String? = nil) -> String {
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sanitizeTypeName(override)
        }
        if let tableName = table.tableName, !tableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sanitizeTypeName(tableName)
        }
        if let fallbackFileName, !fallbackFileName.isEmpty {
            let name = URL(filePath: fallbackFileName).deletingPathExtension().lastPathComponent
            if !name.isEmpty {
                return sanitizeTypeName(name)
            }
        }
        return "ParadoxTable"
    }

    private static func renderProperty(for descriptor: ParadoxFieldDescriptor, index: Int, isPrimaryKey: Bool, usedNames: inout Set<String>) -> String {
        let originalName = descriptor.name ?? "Field \(index + 1)"
        let propertyName = makeUniquePropertyName(from: originalName, fallbackIndex: index, usedNames: &usedNames)
        let swiftType = swiftType(for: descriptor)
        let commentSuffix = isPrimaryKey ? " [Primary Key]" : ""
        let comment = "    /// Paradox field `\(originalName)` – \(descriptor.typeDescription) (\(descriptor.length) bytes)\(commentSuffix)"
        let attributePrefix = isPrimaryKey ? "    @Attribute(.unique) " : "    "
        return "\(comment)\n\(attributePrefix)var \(propertyName): \(swiftType) = nil"
    }

    private static func swiftType(for descriptor: ParadoxFieldDescriptor) -> String {
        switch descriptor.typeCode {
        case 0x01: // Alpha
            return "String?"
        case 0x02: // Date
            return "Date?"
        case 0x03, 0x04, 0x16: // Short, Long, Auto increment
            return "Int?"
        case 0x05: // Currency
            return "Decimal?"
        case 0x06, 0x17: // Number, BCD
            return "Double?"
        case 0x07, 0x09: // Logical
            return "Bool?"
        case 0x08, 0x0C, 0x0E: // Memo variants
            return "String?"
        case 0x0D, 0x0F, 0x10, 0x18: // Binary/OLE/Graphic/Bytes
            return "Data?"
        case 0x14: // Time
            return "TimeInterval?"
        case 0x15: // Timestamp
            return "Date?"
        default:
            return "Data?"
        }
    }

    private static func sanitizeTypeName(_ raw: String) -> String {
        let components = raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
        let titleCased = components.map { component -> String in
            let lower = component.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined()
        let sanitized = titleCased.isEmpty ? "ParadoxTable" : titleCased
        if sanitized.first?.isNumber == true {
            return "Table\(sanitized)"
        }
        return sanitized
    }

    private static func makeUniquePropertyName(from raw: String, fallbackIndex: Int, usedNames: inout Set<String>) -> String {
        let components = raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
        guard !components.isEmpty else {
            return uniquedCandidate("field\(fallbackIndex)", usedNames: &usedNames)
        }
        let first = components[0].lowercased()
        let rest = components.dropFirst().map { part -> String in
            let lower = part.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
        var candidate = ([first] + rest).joined()
        if candidate.first?.isNumber == true {
            candidate = "field" + candidate
        }
        if candidate.isEmpty {
            candidate = "field\(fallbackIndex)"
        }
        return uniquedCandidate(candidate, usedNames: &usedNames)
    }

    private static func uniquedCandidate(_ base: String, usedNames: inout Set<String>) -> String {
        if !usedNames.contains(base) {
            usedNames.insert(base)
            return base
        }
        var counter = 2
        while true {
            let candidate = "\(base)_\(counter)"
            if !usedNames.contains(candidate) {
                usedNames.insert(candidate)
                return candidate
            }
            counter += 1
        }
    }
}
