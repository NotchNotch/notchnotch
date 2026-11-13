import AppKit
import ScreenCaptureKit
import NotchCore
import os

/// Hidden menu bar items' own images, with Screen Recording: each item's
/// window captured once when the notch opens, never recorded, kept only in
/// memory. Without the grant, items keep their app's icon.
@MainActor @Observable final class MenuBarImages {
    /// By item id; an item keeps its last image until a new one comes.
    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows macOS's prompt the first time; after that, Privacy & Security.
    static func request() {
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        images = [:]
    }

    /// Captures `items` from their windows, which needn't be on the screen: those pushed off the menu bar still draw.
    func capture(_ items: [MenuBarItem], windows: [MenuBarWindow]) {
        guard task == nil, Self.isGranted else { return }
        let wanted = items.compactMap { item in MenuBarLayout.window(of: item, in: windows).map { (item.id, $0.id) } }
        guard !wanted.isEmpty else { return }
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        task = Task { [weak self] in
            defer { self?.task = nil }
            let content: SCShareableContent
            do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
            catch { Self.log.error("Can't list windows: \(error.localizedDescription, privacy: .public)"); return }
            for (id, number) in wanted {
                guard !Task.isCancelled else { return }
                guard let window = content.windows.first(where: { $0.windowID == number }) else { Self.log.debug("No window \(number) for \(id, privacy: .public)"); continue }
                let configuration = SCStreamConfiguration()
                configuration.width = Int(window.frame.width * scale)
                configuration.height = Int(window.frame.height * scale)
                configuration.showsCursor = false
                guard let captured = try? await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration),
                    let image = Self.icon(from: captured, scale: scale) else { Self.log.debug("Nothing captured for \(id, privacy: .public)"); continue }
                Self.log.debug("Captured \(id, privacy: .public): \(Int(image.size.width))×\(Int(image.size.height)), template \(image.isTemplate)")
                self?.images[id] = image
            }
        }
    }

    private static let log = Logger(subsystem: "dev.notchnotch.app", category: "menu-bar")

    /// Trimmed to what's drawn, and a template when it's grey: the menu bar's
    /// ink may be dark, the notch is black.
    nonisolated private static func icon(from image: CGImage, scale: CGFloat) -> NSImage? {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let bounds = MenuBarImageTone.visibleBounds(rgba: rgba, width: width, height: height),
              let cropped = image.cropping(to: bounds) else { return nil }
        let icon = NSImage(cgImage: cropped, size: NSSize(width: bounds.width / scale, height: bounds.height / scale))
        icon.isTemplate = MenuBarImageTone.isMonochrome(rgba: rgba)
        return icon
    }
}
