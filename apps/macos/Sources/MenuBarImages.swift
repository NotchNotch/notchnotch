import AppKit
import ScreenCaptureKit
import NotchCore
import os

/// Menu bar items' own images, with Screen Recording: each item's window
/// captured once while it's on the screen, never recorded, kept only in
/// memory. Without the grant, items keep their app's icon.
@MainActor @Observable final class MenuBarImages {
    /// By item id; an item keeps its last image until a new one comes.
    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var started = Date.distantPast
    @ObservationIgnored private var pending: [(String, UInt32)] = []
    @ObservationIgnored private var queued: Set<String> = []

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
        pending = []
        queued = []
        images = [:]
    }

    /// Whether every one of `items` has its image.
    func hasImages(for items: [MenuBarItem]) -> Bool { items.allSatisfy { images[$0.id] != nil } }

    /// Captures the items that are on the menu bar now and have no image yet:
    /// ScreenCaptureKit fails for a window off the screen, so the hidden items
    /// are captured while they're shown, for a press, ⌘ or a peek. Calls while
    /// one runs add to it, so a narrow call can't stand in for a wider one.
    func capture(_ items: [MenuBarItem], windows: [MenuBarWindow], visible: ClosedRange<CGFloat>) {
        guard Self.isGranted else { Self.log.notice("Exact icons: no Screen Recording"); return }
        let wanted = items.filter { images[$0.id] == nil && !queued.contains($0.id) }.compactMap { item -> (String, UInt32)? in
            // Under the camera counts: macOS marks it off-screen, but it's drawn and ScreenCaptureKit
            // captures it. Past the menu bar's end, where the divider pushes it, nothing can.
            guard let window = MenuBarLayout.window(of: item, in: windows),
                  window.frame.minX >= visible.lowerBound, window.frame.maxX <= visible.upperBound else { return nil }
            return (item.id, window.id)
        }
        guard !wanted.isEmpty else { return }
        pending += wanted
        queued.formUnion(wanted.map(\.0))
        // ScreenCaptureKit can stall; a capture that never ends mustn't stop every later one.
        if task != nil, Date().timeIntervalSince(started) < 8 { return }
        if task != nil { queued = Set(pending.map(\.0)) }  // the stalled one's batch can be tried again
        task?.cancel()
        started = Date()
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        task = Task { [weak self] in
            var done = 0, tried = 0
            while let self, !Task.isCancelled, !self.pending.isEmpty {
                let batch = self.pending
                self.pending = []
                let content: SCShareableContent
                do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
                catch { Self.log.error("Exact icons: can't list windows: \(error.localizedDescription, privacy: .public)"); break }
                for (id, number) in batch {
                    guard !Task.isCancelled else { return }
                    tried += 1
                    defer { self.queued.remove(id) }
                    guard let window = content.windows.first(where: { $0.windowID == number }) else {
                        Self.log.notice("Exact icons: window \(number) not shareable for \(id, privacy: .public)"); continue
                    }
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(window.frame.width * scale)
                    configuration.height = Int(window.frame.height * scale)
                    configuration.showsCursor = false
                    let captured: CGImage
                    do {
                        captured = try await SCScreenshotManager.captureImage(
                            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
                    } catch {
                        Self.log.notice("Exact icons: \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"); continue
                    }
                    guard let image = Self.icon(from: captured, scale: scale) else {
                        Self.log.notice("Exact icons: \(id, privacy: .public) came back empty, at \(Int(window.frame.minX))"); continue
                    }
                    self.images[id] = image
                    done += 1
                }
            }
            Self.log.notice("Exact icons: \(done) of \(tried) captured")
            if !Task.isCancelled { self?.task = nil }
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
