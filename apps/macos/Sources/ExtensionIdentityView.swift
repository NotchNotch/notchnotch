import AppKit
import SwiftUI
import NotchExtensions

/// An extension's identity in Settings, the install review and consent: its
/// own artwork, or its SF Symbol on an accent tile.
struct ExtensionIdentityView: View {
    let icon: ExtensionIcon
    var size: CGFloat = 28
    var body: some View {
        switch icon {
        case .image:
            ExtensionIconImage(icon: icon, size: size)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.58))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.tint, in: RoundedRectangle(cornerRadius: size * 0.2))
                .accessibilityHidden(true)
        }
    }
}

/// Draws an extension's PNG icon as the author designed it. A file that can
/// no longer be read shows the generic extension symbol.
struct ExtensionIconImage: View {
    let icon: ExtensionIcon
    let size: CGFloat

    var body: some View {
        Group {
            if let url = icon.imageURL,
               let image = ExtensionIconCache.image(at: url) {
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
}
