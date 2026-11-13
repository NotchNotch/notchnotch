import AppKit
import Quartz
import QuickLookThumbnailing
import UniformTypeIdentifiers
import NotchExtensions
import NotchProtocol
import NotchRenderer

/// Does what extensions ask with the files dropped on them. They hold ids,
/// never paths; every action resolves the id through the extension's own
/// handles, so one extension can't reach another's files.
@MainActor
final class FilesService {
    let store: DroppedFileStore
    private let thumbnails = NSCache<NSString, NSImage>()
    private let quickLook = QuickLookPresenter()
    /// Shows the apps that open these files in the notch; without it, a menu at the pointer.
    var presentOpenWith: (@MainActor ([URL]) -> Void)?
    /// Kept while its menu is open.
    private var sharePicker: NSSharingServicePicker?

    init(store: DroppedFileStore) { self.store = store }

    /// Actions that show something or change files need a click in the extension, like `open`.
    static func needsActivation(_ action: FilesAction) -> Bool {
        ![.thumbnail, .read, .release, .keepCopy].contains(action)
    }

    func perform(_ request: FilesRequest, extensionID: String, permissions: [String]) async throws -> JSONValue {
        try request.validate()
        if request.readsContents, !permissions.contains("file-read") {
            throw ProtocolError.invalid("files.\(request.action.rawValue) needs the file-read permission in notchnotch.json.")
        }
        let ids = request.ids ?? []
        func urls() throws -> [URL] {
            let found = ids.compactMap { store.url($0, for: extensionID) }
            guard found.count == ids.count else { throw ProtocolError.invalid("A file is gone, or isn’t this extension’s.") }
            return found
        }
        switch request.action {
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop) else { throw ProtocolError.invalid("AirDrop isn’t available on this Mac.") }
            let items = try urls()
            guard service.canPerform(withItems: items) else { throw ProtocolError.invalid("AirDrop can’t send these.") }
            NSApp.activate()
            service.perform(withItems: items)
        case .open:
            let items = try urls()
            if let app = request.app {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else {
                    throw ProtocolError.invalid("No app with the identifier \(app) is installed.")
                }
                _ = try await NSWorkspace.shared.open(items, withApplicationAt: appURL, configuration: .init())
            } else {
                for url in items { NSWorkspace.shared.open(url) }
            }
        case .share:
            let items = try urls()
            guard let anchor = FileMenus.pointerAnchor() else { throw ProtocolError.invalid("Share needs the notch open.") }
            let picker = NSSharingServicePicker(items: items)
            sharePicker = picker
            picker.show(relativeTo: anchor.rect, of: anchor.view, preferredEdge: .minY)
        case .openWith:
            let items = try urls()
            if let presentOpenWith { presentOpenWith(items) } else { FileMenus.popUpAtPointer(FileMenus.openWith(items)) }
        case .clipboard:
            if let text = request.text {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } else {
                FileMenus.copy(try urls())
            }
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(try urls())
        case .preview:
            quickLook.show(try urls())
        case .thumbnail:
            guard let id = ids.first, let image = await thumbnail(id, for: extensionID, size: CGFloat(request.size ?? 64)),
                  let png = image.pngData() else { return .null }
            return .string("data:image/png;base64," + png.base64EncodedString())
        case .copy, .move:
            let items = try urls()
            guard let folder = await chooseFolder(prompt: request.action == .copy ? "Copy Here" : "Move Here") else { return .bool(false) }
            for (id, url) in zip(ids, items) {
                let target = folder.appendingPathComponent(url.lastPathComponent)
                if request.action == .copy { try FileManager.default.copyItem(at: url, to: target) }
                else {
                    try FileManager.default.moveItem(at: url, to: target)
                    store.replace(id, with: target, for: extensionID)
                }
            }
            return .bool(true)
        case .release:
            store.release(ids, for: extensionID)
        case .keepCopy:
            // The handle store isn't thread-safe; a copy of a very large file briefly holds the main thread.
            let copies = try ids.map { try store.keepCopy($0, for: extensionID) }
            return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(copies))
        case .read:
            guard let url = try urls().first else { return .null }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(request.offset ?? 0))
            let data = try handle.read(upToCount: request.limit ?? FilesRequest.maximumReadBytes) ?? Data()
            if request.as == .base64 { return .string(data.base64EncodedString()) }
            guard let text = String(data: data, encoding: .utf8) else { throw ProtocolError.invalid("This part of the file isn’t UTF-8 text. Read it as base64.") }
            return .string(text)
        case .save:
            guard let name = request.name, let data = request.data.flatMap({ Data(base64Encoded: $0) }) else { return .null }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            guard let url = await FileMenus.choose(panel) else { return .null }
            try data.write(to: url, options: .atomic)
            let file = try store.add(url, for: extensionID)
            return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(file))
        }
        return .null
    }

    /// The file's thumbnail as Finder shows it: its preview, else its icon.
    func thumbnail(_ id: String, for extensionID: String, size: CGFloat) async -> NSImage? {
        let key = "\(extensionID)/\(id)/\(Int(size))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let url = store.url(id, for: extensionID) else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: 2, representationTypes: .all)
        let image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
            ?? NSWorkspace.shared.icon(forFile: url.path)
        thumbnails.setObject(image, forKey: key)
        return image
    }

    private func chooseFolder(prompt: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        return await FileMenus.choose(panel)
    }
}

/// Shows files in the Quick Look panel.
@MainActor
private final class QuickLookPresenter: NSObject, @preconcurrency QLPreviewPanelDataSource {
    private var urls: [URL] = []

    func show(_ urls: [URL]) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate()
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { urls[index] as NSURL }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
