import Foundation
import ImageIO
import UniformTypeIdentifiers
import NotchProtocol

/// What an extension shows as its identity: an SF Symbol drawn by the host, or
/// the extension's own 512×512 PNG from `assets/`, with an optional `@dark`
/// variant for dark backgrounds.
public enum ExtensionIcon: Equatable, Sendable {
    case symbol(String)
    case image(light: URL, dark: URL?)

    public static let fallbackSymbol = "puzzlepiece.extension"
    public static let pixelSize = 512
    public static let maximumBytes = 512 * 1024

    /// Resolves the manifest's icon inside a package that has passed `validate`.
    public init(manifest: ExtensionManifest, directory: URL) {
        guard let names = manifest.iconFiles else {
            self = .symbol(manifest.icon ?? Self.fallbackSymbol)
            return
        }
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        let dark = assets.appendingPathComponent(names.dark)
        self = .image(light: assets.appendingPathComponent(names.light),
                      dark: FileManager.default.fileExists(atPath: dark.path) ? dark : nil)
    }

    /// The icon in the appearance's variant, falling back to the light image.
    public func imageURL(dark: Bool) -> URL? {
        guard case let .image(light, darkURL) = self else { return nil }
        return dark ? (darkURL ?? light) : light
    }

    /// The installer's checks: both files, when declared, are regular PNG files
    /// of exactly 512×512 pixels and at most 512 KiB.
    static func validate(manifest: ExtensionManifest, directory: URL) throws {
        guard let names = manifest.iconFiles else { return }
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        try validateImage(assets.appendingPathComponent(names.light), name: names.light, required: true)
        try validateImage(assets.appendingPathComponent(names.dark), name: names.dark, required: false)
    }

    private static func validateImage(_ url: URL, name: String, required: Bool) throws {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard let values, values.isSymbolicLink != true else {
            if required { throw ProtocolError.invalid("The icon assets/\(name) is missing.") }
            return
        }
        guard values.isRegularFile == true, (1...maximumBytes).contains(values.fileSize ?? 0),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == pixelSize,
              properties[kCGImagePropertyPixelHeight] as? Int == pixelSize else {
            throw ProtocolError.invalid("The icon assets/\(name) must be a 512×512 PNG file of at most 512 KiB.")
        }
    }
}
