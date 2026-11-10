import AppKit
import SwiftUI
import NotchCore
import NotchProtocol
import NotchRenderer
import NotchExtensions

/// Store screenshots: an extension's activities drawn expanded in the notch,
/// on the same wallpaper every time, at 2000 × 1250 pixels.
///
/// They're rendered offscreen from the extension's current snapshot rather than
/// captured from the display, so they need no Screen Recording permission and
/// don't depend on the Mac, its notch or what else is running.
@MainActor
enum StoreScreenshot {
    static let pixelSize = CGSize(width: 2000, height: 1250)
    static let maximumCount = 6
    private static let canvas = CGSize(width: 600, height: 375)

    enum Failure: LocalizedError {
        case nothingToCapture(String)
        case render
        var errorDescription: String? {
            switch self {
            case .nothingToCapture(let name): "\(name) has no activity in the notch right now. Start one, then capture again."
            case .render: "The screenshot couldn’t be drawn."
            }
        }
    }

    /// Writes `1.png`, `2.png`… into `folder`, one per activity or prompt, and
    /// returns them. Older numbered screenshots there are replaced.
    static func capture(_ surfaces: [HostedSurface], record: InstalledExtension, into folder: URL) throws -> [URL] {
        let chosen = Array(surfaces.filter { $0.key.extensionID == record.id }.prefix(maximumCount))
        guard !chosen.isEmpty else { throw Failure.nothingToCapture(record.manifest.name) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for old in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where old.pathExtension == "png" && Int(old.deletingPathExtension().lastPathComponent) != nil {
            try? FileManager.default.removeItem(at: old)
        }
        return try chosen.enumerated().map { index, item in
            let url = folder.appendingPathComponent("\(index + 1).png")
            try png(StoreScreenshotView(item: item, record: record)).write(to: url, options: .atomic)
            return url
        }
    }

    static func png(_ view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view.frame(width: canvas.width, height: canvas.height).environment(\.colorScheme, .dark))
        renderer.scale = pixelSize.width / canvas.width
        renderer.isOpaque = true
        guard let image = renderer.cgImage, image.width == Int(pixelSize.width), image.height == Int(pixelSize.height) else { throw Failure.render }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
        return data
    }
}

/// The top of a Mac display: wallpaper, menu bar, and the expanded notch.
private struct StoreScreenshotView: View {
    let item: HostedSurface
    let record: InstalledExtension
    private let geometry = NotchGeometry(cameraWidth: 200, cameraHeight: 32, attached: true)

    var body: some View {
        ZStack(alignment: .top) {
            StoreWallpaper()
            Rectangle().fill(.black.opacity(0.18)).frame(height: 24)
            notch
        }
        .clipped()
    }

    private var notch: some View {
        let width = geometry.expandedWidth
        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 28)
            .frame(height: geometry.cameraHeight + 8)
            VStack(spacing: 14) {
                if item.surface.kind == .prompt { promptHeader }
                NativeNodeView(node: item.surface.expanded) { _, _ in }
            }
            .padding(.horizontal, 28)
            Color.clear.frame(height: NotchGeometry.expandedBottomPadding + 6)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                NotchSilhouette(bodyWidth: width, bodyHeight: proxy.size.height,
                                shoulder: geometry.shoulderRadius(presentation: .expanded),
                                bottomRadius: geometry.bottomRadius(presentation: .expanded), attached: true)
                    .fill(.black)
                    .frame(width: width + 2 * geometry.shoulderRadius(presentation: .expanded))
                    .offset(x: -geometry.shoulderRadius(presentation: .expanded))
                    .shadow(color: .black.opacity(0.34), radius: 16, y: 7)
            }
        }
        .foregroundStyle(NotchTheme.Ink.primary)
    }

    private var promptHeader: some View {
        HStack(spacing: 10) {
            ExtensionIdentityView(icon: record.icon, size: NotchTheme.iconTile)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.surface.title).font(NotchTheme.font(.headline)).foregroundStyle(NotchTheme.Ink.primary)
                Text(record.manifest.name).font(NotchTheme.font(.caption)).foregroundStyle(NotchTheme.Ink.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A calm gradient so every extension's screenshots share one background,
/// as the Store asks, and the black notch stands out.
struct StoreWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.42), Color(red: 0.42, green: 0.27, blue: 0.55),
                                    Color(red: 0.86, green: 0.52, blue: 0.48)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.55, green: 0.70, blue: 1).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.2, y: 0.9), startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(red: 1, green: 0.78, blue: 0.55).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.85, y: 0.15), startRadius: 10, endRadius: 360)
        }
    }
}
