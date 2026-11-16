import AppKit
import SwiftUI
import NotchExtensions

/// An extension's identity in Settings, the install review and consent: its
/// own artwork, or its SF Symbol on an accent tile.
///
/// `tile` drops the artwork's transparent margin (macOS icons draw in the
/// middle 80%), so a small icon fills its frame like a sidebar tile does.
struct ExtensionIdentityView: View {
    let icon: ExtensionIcon
    var size: CGFloat = 28
    var tile = false
    var body: some View {
        switch icon {
        case .image:
            ExtensionIconImage(icon: icon, size: size, trimmed: tile)
        case .symbol(let name):
            if tile {
                SettingsIconTile(symbol: name, color: .accentColor, size: size)
            } else {
                Image(systemName: name)
                    .font(.system(size: size * 0.58))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(.tint, in: RoundedRectangle(cornerRadius: size * 0.2))
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Draws an extension's PNG icon as the author designed it. A file that can
/// no longer be read shows the generic extension symbol.
struct ExtensionIconImage: View {
    let icon: ExtensionIcon
    let size: CGFloat
    var trimmed = false

    var body: some View {
        Group {
            if let url = icon.imageURL,
               let image = trimmed ? ExtensionIconCache.trimmedImage(at: url) : ExtensionIconCache.image(at: url) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: ExtensionIcon.fallbackSymbol).resizable().aspectRatio(contentMode: .fit)
                    .padding(size * 0.15).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Decoded icons, keyed by file and modification date so an updated
/// extension shows its new artwork without restarting the app.
@MainActor
enum ExtensionIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    static func image(at url: URL) -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(url.path)|\(modified?.timeIntervalSinceReferenceDate ?? 0)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// The icon cut to its drawn part; the same icon when it fills its canvas.
    static func trimmedImage(at url: URL) -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "trimmed|\(url.path)|\(modified?.timeIntervalSinceReferenceDate ?? 0)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = image(at: url) else { return nil }
        let trimmed = trim(image) ?? image
        cache.setObject(trimmed, forKey: key)
        return trimmed
    }

    /// Crops to the square around every pixel at least half opaque, which
    /// leaves out the soft shadow macOS icons carry in their margin.
    private static func trim(_ image: NSImage) -> NSImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= 128 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let side = max(maxX - minX, maxY - minY) + 1
        let rect = CGRect(x: (minX + maxX + 1 - side) / 2, y: (minY + maxY + 1 - side) / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width < CGFloat(width) || rect.height < CGFloat(height), let cropped = source.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }
}
