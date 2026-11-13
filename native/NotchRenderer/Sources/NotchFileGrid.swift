import SwiftUI
import AppKit
import NotchCore
import NotchProtocol

/// Many files, laid out so they always fit (`FileGridLayout`): up to six
/// columns and three rows; past that, stacks by kind that open in place.
/// Files select like in Finder; every file, selection and stack drags out.
struct NotchFileGrid: View {
    let files: [DroppedFile]
    /// The extension's selection; nil when it doesn't select.
    var selected: [String]? = nil
    var removable = false
    /// The extension's event: `{"select" | "remove" | "dragOut": [ids]}`.
    var action: String? = nil
    var onEvent: (String, String?) -> Void = { _, _ in }
    @State private var open: FileStack.Kind?
    /// Drawn at once on a click; the extension's `selected` catches up and wins.
    @State private var selection: Set<String> = []
    @State private var anchor: String?
    @Environment(\.notchFiles) private var provider
    @Environment(\.notchTile) private var tile
    @Environment(\.notchTileOpen) private var openTile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84) }
    private var columns: Int { FileGridLayout.columns(for: files.count) }
    private var stacks: [FileStack] { FileStack.group(files) }

    var body: some View {
        if tile { tileStack } else { grid }
    }

    /// In a tile: every file as one fanned stack. Dragging it takes them all; a click opens the tile.
    private var tileStack: some View {
        FileFan(files: files, edge: 34, spread: hovered)
            .frame(width: 46, height: 42)
            .contentShape(Rectangle())
            .overlay(FilesDragSource(urls: { files.compactMap { provider?.url($0) } },
                                     onDragStart: { provider?.draggingOut() },
                                     onDragEnd: { send("dragOut", files) },
                                     onClick: { _, _ in openTile?() }))
            .onHover { inside in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovered = inside } }
            .accessibilityHidden(true)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 6) {
            if FileGridLayout.stacks(files.count) {
                if let open, let stack = stacks.first(where: { $0.kind == open }) {
                    Button { withAnimation(spring) { self.open = nil } } label: {
                        Label("\(stack.kind.title) · \(stack.files.count)", systemImage: "chevron.left")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(NotchTheme.Ink.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    grid(stack.files)
                } else {
                    LazyVGrid(columns: layout, alignment: .leading, spacing: FileGridLayout.spacing) {
                        ForEach(stacks) { stack in
                            StackCell(stack: stack, onDragEnd: { send("dragOut", stack.files) }) {
                                withAnimation(spring) { open = stack.kind }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            } else {
                grid(files)
            }
        }
        .frame(width: FileGridLayout.width(columns: columns), alignment: .leading)
        .animation(spring, value: files.map(\.id))
        .onChange(of: FileGridLayout.stacks(files.count)) { _, stacked in if !stacked { open = nil } }
        .onAppear { selection = Set(selected ?? []) }
        .onChange(of: selected) { _, ids in selection = Set(ids ?? []) }
    }

    private var layout: [GridItem] {
        Array(repeating: GridItem(.fixed(FileGridLayout.cellWidth), spacing: FileGridLayout.spacing), count: columns)
    }

    /// Files one by one; if they don't all fit, the last cell shows the rest in Finder.
    private func grid(_ shown: [DroppedFile]) -> some View {
        let visible = FileGridLayout.visible(shown.count)
        return LazyVGrid(columns: layout, alignment: .leading, spacing: FileGridLayout.spacing) {
            ForEach(shown.prefix(visible.shown), id: \.id) { file in
                cell(file, in: shown)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if visible.more > 0 {
                let rest = Array(shown.dropFirst(visible.shown))
                Button {
                    let urls = rest.compactMap { provider?.url($0) }
                    if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                } label: {
                    VStack(spacing: 5) {
                        Text("+\(visible.more)").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
                        Text("Show in Finder").font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .frame(width: FileGridLayout.cellWidth).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(visible.more) more files. Show them in Finder")
            }
        }
    }

    private func cell(_ file: DroppedFile, in order: [DroppedFile]) -> some View {
        FileCell(file: file, selected: selection.contains(file.id),
                 targets: { targets(for: file) },
                 onClick: { modifiers, clicks in click(file, modifiers: modifiers, clicks: clicks, in: order) },
                 onDragEnd: { send("dragOut", targets(for: file)) },
                 menu: { menu(for: file) })
    }

    /// What a gesture on this file acts on: the selection when it's part of it, else just the file.
    private func targets(for file: DroppedFile) -> [DroppedFile] {
        selection.contains(file.id) ? files.filter { selection.contains($0.id) } : [file]
    }

    private func click(_ file: DroppedFile, modifiers: NSEvent.ModifierFlags, clicks: Int, in order: [DroppedFile]) {
        if clicks >= 2 {
            provider?.perform(.open, targets(for: file))
            return
        }
        guard selected != nil else { return }
        var next = selection
        if next.contains(file.id) {
            // A selected file lets go with any click: the notch has no empty space to click, and a
            // file picked by mistake in a ⇧ range comes out without starting over.
            next.remove(file.id)
        } else if modifiers.contains(.command) {
            next.insert(file.id)
            anchor = file.id
        } else if modifiers.contains(.shift), let anchor, let from = order.firstIndex(where: { $0.id == anchor }),
                  let to = order.firstIndex(where: { $0.id == file.id }) {
            next.formUnion(order[min(from, to)...max(from, to)].map(\.id))
        } else {
            next = [file.id]
            anchor = file.id
        }
        withAnimation(.easeOut(duration: 0.12)) { selection = next }
        send("select", files.filter { next.contains($0.id) })
    }

    private func menu(for file: DroppedFile) -> NSMenu {
        let provider = provider
        let targets = targets(for: file)
        let urls = targets.compactMap { provider?.url($0) }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Quick Look", symbol: "eye") { provider?.perform(.preview, targets) })
        menu.addItem(ClosureMenuItem("Open", symbol: "arrow.up.forward.app") { provider?.perform(.open, targets) })
        let openWith = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        openWith.submenu = FileMenus.openWith(urls)
        menu.addItem(openWith)
        menu.addItem(ClosureMenuItem("Show in Finder", symbol: "folder") { provider?.perform(.reveal, targets) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(targets.count == 1 ? "Copy" : "Copy \(targets.count) Items", symbol: "doc.on.doc") { FileMenus.copy(urls) })
        menu.addItem(FileMenus.shareItem(urls))
        if removable {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(targets.count == 1 ? "Remove" : "Remove \(targets.count) Items", symbol: "minus.circle") {
                send("remove", targets)
            })
        }
        return menu
    }

    private func send(_ event: String, _ files: [DroppedFile]) {
        guard let action, !files.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: [event: files.map(\.id)]),
              let json = String(data: data, encoding: .utf8) else { return }
        onEvent(action, json)
    }
}

/// One file in the grid. A click selects, a double-click opens, a drag takes
/// it (or the selection it's in) out, and a right-click shows its menu.
private struct FileCell: View {
    let file: DroppedFile
    let selected: Bool
    let targets: () -> [DroppedFile]
    let onClick: (NSEvent.ModifierFlags, Int) -> Void
    let onDragEnd: () -> Void
    let menu: () -> NSMenu
    @Environment(\.notchFiles) private var provider
    @Environment(\.notchAccent) private var accent
    @State private var hovered = false

    var body: some View {
        let tint = accent?.color ?? .accentColor
        FileCellLabel(file: file, selected: selected)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? tint.opacity(0.18) : .white.opacity(hovered ? 0.06 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(FilesDragSource(urls: { targets().compactMap { provider?.url($0) } },
                                     onDragStart: { provider?.draggingOut() }, onDragEnd: onDragEnd,
                                     onClick: onClick, menu: menu))
            .onHover { hovered = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(file.name)
            .accessibilityValue(file.detail)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onClick([], 1) }
            .accessibilityAction(named: "Open") { onClick([], 2) }
            .help(file.name)
    }
}

/// A stack of one kind: its first files fanned like a Dock stack, with its
/// count. A click opens it; dragging it takes every file in it.
private struct StackCell: View {
    let stack: FileStack
    let onDragEnd: () -> Void
    let action: () -> Void
    @Environment(\.notchFiles) private var provider
    @State private var hovered = false

    private var count: String {
        let noun = stack.kind == .folders ? "folder" : "file"
        return "\(stack.files.count) \(noun)\(stack.files.count == 1 ? "" : "s")"
    }

    private var fan: some View { FileFan(files: stack.files, edge: 44, spread: hovered) }

    var body: some View {
        VStack(spacing: 5) {
            fan.frame(width: 52, height: 52)
            Text(stack.kind.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Text(count)
                .font(.system(size: 10)).foregroundStyle(NotchTheme.Ink.secondary)
        }
        .frame(width: FileGridLayout.cellWidth).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovered ? 0.08 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(FilesDragSource(urls: { stack.files.compactMap { provider?.url($0) } },
                                 onDragStart: { provider?.draggingOut() }, onDragEnd: onDragEnd,
                                 onClick: { _, _ in action() }))
        .onHover { inside in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovered = inside } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stack.kind.title), \(stack.files.count) files")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// The first three files, the first on top, the others turned behind it like a Dock stack.
struct FileFan: View {
    let files: [DroppedFile]
    let edge: CGFloat
    let spread: Bool

    var body: some View {
        let top = Array(files.prefix(3))
        ZStack {
            ForEach(top.indices.reversed(), id: \.self) { index in
                let angle = Double(index) * (spread ? 9 : 6)
                let shift = CGFloat(index) * (spread ? 5 : 3)
                FileThumbnail(file: top[index], edge: edge)
                    .rotationEffect(.degrees(angle))
                    .offset(x: shift, y: -1.5 * CGFloat(index))
            }
        }
    }
}

/// Clicks call `onClick` with their modifiers and count; a drag carries every
/// URL at once, which SwiftUI's `onDrag` (one item) can't; a right-click shows `menu`.
private struct FilesDragSource: NSViewRepresentable {
    let urls: () -> [URL]
    let onDragStart: () -> Void
    /// The files landed somewhere: Finder, Mail, any app.
    var onDragEnd: () -> Void = {}
    let onClick: (NSEvent.ModifierFlags, Int) -> Void
    var menu: (() -> NSMenu)? = nil

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.urls = urls; view.onDragStart = onDragStart; view.onDragEnd = onDragEnd
        view.onClick = onClick; view.makeMenu = menu
    }

    final class SourceView: NSView, NSDraggingSource {
        var urls: () -> [URL] = { [] }
        var onDragStart: () -> Void = {}
        var onDragEnd: () -> Void = {}
        var onClick: (NSEvent.ModifierFlags, Int) -> Void = { _, _ in }
        var makeMenu: (() -> NSMenu)?
        private var start: NSPoint?
        private var dragging = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { start = event.locationInWindow; dragging = false }
        override func mouseUp(with event: NSEvent) {
            if !dragging, start != nil { onClick(event.modifierFlags.intersection(.deviceIndependentFlagsMask), event.clickCount) }
            start = nil
        }
        override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }
        override func mouseDragged(with event: NSEvent) {
            guard let start, !dragging, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
            let urls = urls()
            guard !urls.isEmpty else { return }
            dragging = true
            onDragStart()
            let local = convert(event.locationInWindow, from: nil)
            let items = urls.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                item.setDraggingFrame(NSRect(x: local.x - 24 + CGFloat(min(index, 4)) * 4, y: local.y - 24, width: 48, height: 48), contents: icon)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .generic] : []
        }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            if !operation.isEmpty { onDragEnd() }
        }
    }
}
