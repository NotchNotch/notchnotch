import SwiftUI
import UniformTypeIdentifiers
import NotchCore
import NotchProtocol
import NotchRenderer

/// The notch while something is dragged over it: the zones that take it, at
/// Home's tile size. The zone under the pointer grows and takes its
/// extension's color; letting go hands the items to that extension.
struct DropView: View {
    let targets: [DropTarget]
    let items: [DraggedItem]
    let showsAll: Bool
    let width: CGFloat
    let accent: (String) -> NotchTheme.Accent?
    let onDrop: (DropTarget) -> Void
    let onShowAll: () -> Void
    @State private var targeted: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78) }

    var body: some View {
        let arrangement = DropArrangement(targets)
        let shown = showsAll ? Array(targets.prefix(12)) : arrangement.shown
        Group {
            if targets.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "nosign").font(.system(size: 14, weight: .medium))
                    Text("Nothing here takes \(Self.describe(items))").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: width, height: HomeLayout.tileHeight)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: HomeLayout.spacing), count: min(4, max(shown.count + (showsMore(arrangement) ? 1 : 0), 1))),
                          spacing: HomeLayout.spacing) {
                    ForEach(shown) { target in
                        zone(target)
                    }
                    if showsMore(arrangement) { more(count: arrangement.hidden.count) }
                }
                .frame(width: width)
            }
        }
        .animation(spring, value: targeted)
        .animation(spring, value: showsAll)
    }

    private func showsMore(_ arrangement: DropArrangement) -> Bool { !showsAll && arrangement.showsMore }

    private func zone(_ target: DropTarget) -> some View {
        let hovered = targeted == target.id
        let color = accent(target.extensionID)?.color ?? .white
        return VStack(spacing: 5) {
            Image(systemName: target.zone.icon ?? "tray.and.arrow.down")
                .font(.system(size: 19, weight: .medium))
                .symbolEffect(.bounce, value: hovered)
            Text(hovered ? "\(target.zone.title) · \(Self.count(items))" : target.zone.title)
                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                .contentTransition(.opacity)
        }
        .foregroundStyle(hovered ? color : .white.opacity(0.78))
        .frame(maxWidth: .infinity).frame(height: HomeLayout.tileHeight)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hovered ? color.opacity(0.2) : .white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(hovered ? color.opacity(0.9) : .white.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: hovered ? [] : [5, 4])))
        .scaleEffect(hovered && !reduceMotion ? 1.06 : 1)
        .opacity(targeted == nil || hovered ? 1 : 0.55)
        .zIndex(hovered ? 1 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDrop(of: [.item], isTargeted: binding(target.id)) { _ in
            AppDelegate.debug("dropped on \(target.id)")
            onDrop(target)
            return true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(target.zone.title)
    }

    /// Rests on More a moment to see every zone, like a spring-loaded folder.
    private func more(count: Int) -> some View {
        let hovered = targeted == "more"
        return VStack(spacing: 5) {
            Image(systemName: "ellipsis.circle").font(.system(size: 19, weight: .medium))
            Text("\(count) more").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.6))
        .frame(maxWidth: .infinity).frame(height: HomeLayout.tileHeight)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(hovered ? 0.14 : 0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDrop(of: [.item], isTargeted: binding("more")) { _ in false }
        .task(id: hovered) {
            guard hovered else { return }
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { onShowAll() }
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { targeted == id }, set: { inside in
            if inside { targeted = id } else if targeted == id { targeted = nil }
        })
    }

    /// "1 file", "3 folders", "2 items".
    static func count(_ items: [DraggedItem]) -> String {
        let kinds = Set(items.map(\.kind))
        guard kinds.count == 1, let kind = kinds.first else { return "\(items.count) items" }
        let noun = switch kind { case .file: "file"; case .folder: "folder"; case .url: "link"; case .text: "text" }
        return "\(items.count) \(noun)\(items.count == 1 ? "" : "s")"
    }

    /// "this file", "3 folders", "2 items".
    static func describe(_ items: [DraggedItem]) -> String {
        let kinds = Set(items.map(\.kind))
        let count = items.count
        guard kinds.count == 1, let kind = kinds.first else { return "\(count) items" }
        let (one, many) = switch kind {
        case .file: ("this file", "files")
        case .folder: ("this folder", "folders")
        case .url: ("this link", "links")
        case .text: ("this text", "texts")
        }
        return count == 1 ? one : "\(count) \(many)"
    }
}
