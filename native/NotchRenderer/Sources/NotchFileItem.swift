import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NotchProtocol

/// Turns an extension's file handles into what the notch draws: the file's
/// location (for dragging it out) and its thumbnail. The app provides it;
/// handles belong to one extension, so it's set per extension's tree.
public struct NotchFiles: Sendable {
    public var url: @MainActor @Sendable (DroppedFile) -> URL?
    public var thumbnail: @Sendable (DroppedFile, CGFloat) async -> NSImage?
    /// A file is being dragged out of the notch: it mustn't open the drop zones there.
    public var draggingOut: @MainActor @Sendable () -> Void
    /// Quick Look, Open and Show in Finder from a file's menu, done by the app.
    public var perform: @MainActor @Sendable (FilesAction, [DroppedFile]) -> Void
    public init(url: @escaping @MainActor @Sendable (DroppedFile) -> URL?,
                thumbnail: @escaping @Sendable (DroppedFile, CGFloat) async -> NSImage?,
                draggingOut: @escaping @MainActor @Sendable () -> Void = {},
                perform: @escaping @MainActor @Sendable (FilesAction, [DroppedFile]) -> Void = { _, _ in }) {
        self.url = url; self.thumbnail = thumbnail; self.draggingOut = draggingOut; self.perform = perform
    }
}

extension EnvironmentValues {
    @Entry public var notchFiles: NotchFiles? = nil
}

/// A dropped file as Finder shows it: its real thumbnail, else its icon (a
/// folder is the macOS folder), with its name and size. In expanded content
/// it drags back out to Finder or any app.
struct NotchFileItem: View {
    let file: DroppedFile
    let compact: Bool
    @Environment(\.notchFiles) private var files
    @Environment(\.notchTile) private var tile

    private var edge: CGFloat { compact && !tile ? 18 : tile ? 34 : 52 }

    var body: some View {
        Group {
            if compact || tile {
                HStack(spacing: 6) {
                    image
                    Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                }
            } else {
                FileCellLabel(file: file)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onDrag {
                    files?.draggingOut()
                    return files?.url(file).flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
                }
                .contextMenu {
                    if let files {
                        Button("Quick Look", systemImage: "eye") { files.perform(.preview, [file]) }
                        Button("Open", systemImage: "arrow.up.forward.app") { files.perform(.open, [file]) }
                        Button("Show in Finder", systemImage: "folder") { files.perform(.reveal, [file]) }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(file.name)
        .accessibilityValue(detail)
        .help(file.name)
    }

    private var image: some View { FileThumbnail(file: file, edge: edge) }

    private var detail: String { file.detail }
}

/// A file in a grid cell: its thumbnail, name and size. With `selected`, the
/// name sits on the accent like Finder's selection.
struct FileCellLabel: View {
    let file: DroppedFile
    var selected = false
    @Environment(\.notchAccent) private var accent

    var body: some View {
        VStack(spacing: 5) {
            FileThumbnail(file: file, edge: 52).frame(height: 52)
            Text(file.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, selected ? 5 : 0).padding(.vertical, selected ? 1 : 0)
                .background(Capsule().fill(selected ? (accent?.color ?? .accentColor).opacity(0.85) : .clear))
            Text(file.detail).font(.system(size: 10)).foregroundStyle(NotchTheme.Ink.secondary).lineLimit(1)
        }
        .frame(width: 78)
        .padding(.vertical, 8)
    }
}

extension DroppedFile {
    var detail: String { kind == .folder ? "Folder" : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
}

/// A file's real thumbnail, or until it arrives (or when there is none) the
/// icon macOS uses for its type.
struct FileThumbnail: View {
    let file: DroppedFile
    let edge: CGFloat
    @Environment(\.notchFiles) private var files
    @State private var thumbnail: NSImage?

    var body: some View {
        Image(nsImage: thumbnail ?? icon)
            .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            .frame(width: edge, height: edge)
            .shadow(color: .black.opacity(thumbnail == nil ? 0 : 0.35), radius: 2, y: 1)
            .task(id: file.id) { thumbnail = await files?.thumbnail(file, edge * 2) }
    }

    private var icon: NSImage {
        if file.kind == .folder { return NSWorkspace.shared.icon(for: .folder) }
        return NSWorkspace.shared.icon(for: UTType(file.type) ?? .data)
    }
}
