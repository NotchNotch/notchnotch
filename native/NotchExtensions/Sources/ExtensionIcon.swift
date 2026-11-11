import Foundation
import ImageIO
import UniformTypeIdentifiers
import NotchProtocol

/// What an extension shows as its identity: an SF Symbol drawn by the host, or
/// the extension's own 512×512 PNG from `assets/`. One image serves every
/// appearance: the icon is a colored tile, readable on light and dark alike.
public enum ExtensionIcon: Equatable, Sendable {
    case symbol(String)
    case image(URL)

    public static let fallbackSymbol = "puzzlepiece.extension"
    public static let pixelSize = 512
    public static let maximumBytes = 512 * 1024

    /// Resolves the manifest's icon inside a package that has passed `validate`.
    public init(manifest: ExtensionManifest, directory: URL) {
        guard let name = manifest.iconFile else {
            self = .symbol(manifest.icon ?? Self.fallbackSymbol)
            return
        }
        self = .image(directory.appendingPathComponent("assets", isDirectory: true).appendingPathComponent(name))
    }

    public var imageURL: URL? {
        guard case let .image(url) = self else { return nil }
        return url
    }

    /// The installer's checks: the declared file is a regular PNG file of
    /// exactly 512×512 pixels and at most 512 KiB.
    static func validate(manifest: ExtensionManifest, directory: URL) throws {
        guard let name = manifest.iconFile else { return }
        let url = directory.appendingPathComponent("assets", isDirectory: true).appendingPathComponent(name)
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard let values, values.isSymbolicLink != true else {
            throw ProtocolError.invalid("The icon assets/\(name) is missing.")
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
