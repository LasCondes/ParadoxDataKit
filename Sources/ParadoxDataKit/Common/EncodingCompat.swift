import Foundation

#if !canImport(Darwin)
extension String.Encoding {
    public static let windowsCP1252 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsLatin1.rawValue)
        )
    )
}
#endif
