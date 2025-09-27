import Foundation

/// Represents the text contents of a Paradox QBE (`.qbe`) query file.
public struct ParadoxQuery {
    public let text: String
    public let encodingUsed: String.Encoding

    /// Creates a query by decoding the given file data.
    /// - Parameter data: The raw bytes of the `.qbe` file.
    public init(data: Data) {
        if let windowsText = String(data: data, encoding: .windowsCP1252) {
            self.text = windowsText
            self.encodingUsed = .windowsCP1252
        } else if let ansiText = String(data: data, encoding: .ascii) {
            self.text = ansiText
            self.encodingUsed = .ascii
        } else {
            let fallback = data.map { byte -> String in
                guard let scalar = UnicodeScalar(Int(byte)) else { return "" }
                return String(Character(scalar))
            }
            self.text = fallback.joined()
            self.encodingUsed = .ascii
        }
    }
}
