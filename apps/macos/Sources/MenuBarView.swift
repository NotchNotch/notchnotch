import SwiftUI
import AppKit
import NotchCore
import NotchRenderer

/// A hidden menu bar item's icon. System items all belong to Control Center,
/// so they get the symbol macOS uses for them; others get their app's icon.
struct MenuBarIcon: View {
    let item: MenuBarItem
    let size: CGFloat
    /// The item's own image, with Screen Recording. A wide one, a clock's
    /// date or a reading, would shrink to nothing: those keep the symbol.
    var image: NSImage? = nil

    var body: some View {
        if let image, image.size.width <= image.size.height * 1.8 {
            Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
                .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size, height: size * 0.92)
                .frame(width: size, height: size)
        } else if let symbol = Self.symbol(for: item) {
            Image(systemName: symbol).font(.system(size: size * 0.78, weight: .medium))
                .foregroundStyle(.white.opacity(0.85)).frame(width: size, height: size)
        } else if item.bundleID == nil {
            // A helper outside any app has no icon of its own: its initial, until exact images.
            Text(item.name.prefix(1).uppercased()).font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85)).frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(.white.opacity(0.16)))
        } else {
            Image(nsImage: Self.icon(of: item.pid)).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fit).frame(width: size, height: size)
        }
    }

    private static func icon(of pid: Int32) -> NSImage {
        NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(for: .application)
    }

    /// Control Center's items and the input menu, by identifier or app.
    static func symbol(for item: MenuBarItem) -> String? {
        if item.bundleID == "com.apple.TextInputMenuAgent" { return "keyboard" }
        guard let identifier = item.identifier else { return nil }
        let symbols: [String: String] = [
            "battery": "battery.75percent", "wifi": "wifi", "bluetooth": "bluetooth" , "clock": "clock",
            "now-playing": "play.circle", "screen-mirroring": "rectangle.on.rectangle", "controlcenter": "switch.2",
            "focusmode": "moon", "sound": "speaker.wave.2", "display": "sun.max", "user": "person.crop.circle",
            "airdrop": "dot.radiowaves.left.and.right", "keyboardbrightness": "light.max", "accessibility": "accessibility",
            "hearing": "ear", "stagemanager": "rectangle.split.3x1", "spotlight": "magnifyingglass", "siri": "mic",
            "timemachine": "clock.arrow.circlepath", "vpn": "network.badge.shield.half.filled",
        ]
        let key = identifier.replacingOccurrences(of: "com.apple.menuextra.", with: "")
        return symbols[key] ?? (identifier.hasPrefix("com.apple.menuextra.") ? "circle.grid.2x2" : nil)
    }
}

/// The header's left side: the hidden items, in menu bar order. Up to five;
/// past that, four and `+N`, which opens every one as tiles.
struct MenuBarStrip: View {
    let items: [MenuBarItem]
    var images: [String: NSImage] = [:]
    let onPress: (MenuBarItem) -> Void
    let onShowAll: () -> Void
    @State private var hovered: String?

    var body: some View {
        let layout = MenuBarLayout.header(count: items.count)
        HStack(spacing: 2) {
            ForEach(items.prefix(layout.shown)) { item in
                Button { onPress(item) } label: {
                    MenuBarIcon(item: item, size: 15, image: images[item.id])
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(hovered == item.id ? 0.14 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in if inside { hovered = item.id } else if hovered == item.id { hovered = nil } }
                .help(item.name)
                .accessibilityLabel("\(item.name), menu bar")
            }
            if layout.more > 0 {
                Button(action: onShowAll) {
                    Text("+\(layout.more)").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 6).frame(height: 20)
                        .background(Capsule().fill(.white.opacity(hovered == "more" ? 0.18 : 0.1)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? "more" : (hovered == "more" ? nil : hovered) }
                .help("\(layout.more) more menu bar items")
                .accessibilityLabel("\(layout.more) more menu bar items")
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// Every hidden menu bar item as a tile at Home's size, from `+N`, and a way
/// to choose them.
struct MenuBarPage: View {
    let items: [MenuBarItem]
    var images: [String: NSImage] = [:]
    let width: CGFloat
    let onPress: (MenuBarItem) -> Void
    let onRearrange: () -> Void
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hidden from the menu bar").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.Ink.secondary).padding(.leading, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: HomeLayout.spacing), count: HomeLayout.minimumColumns),
                      spacing: HomeLayout.spacing) {
                ForEach(items.prefix(12)) { item in tile(item) }
            }
            Button(action: onRearrange) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .semibold))
                    Text("Rearrange menu bar…").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(hovered == "rearrange" ? 0.95 : 0.6))
                .padding(.horizontal, 9).frame(height: 22)
                .background(Capsule().fill(.white.opacity(hovered == "rearrange" ? 0.14 : 0)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { inside in hovered = inside ? "rearrange" : (hovered == "rearrange" ? nil : hovered) }
            .help("Shows these in the menu bar; hold ⌘ and drag one across the divider")
            .frame(maxWidth: .infinity)
        }
        .frame(width: width)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: hovered)
    }

    private func tile(_ item: MenuBarItem) -> some View {
        let isHovered = hovered == item.id
        return Button { onPress(item) } label: {
            VStack(spacing: 6) {
                MenuBarIcon(item: item, size: 24, image: images[item.id])
                Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .foregroundStyle(.white.opacity(isHovered ? 1 : 0.82)).padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity).frame(height: HomeLayout.tileHeight)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(isHovered ? 0.16 : 0.07)))
            .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { hovered = item.id } else if hovered == item.id { hovered = nil } }
        .accessibilityLabel("\(item.name), menu bar")
    }
}
