import SwiftUI
import NotchCore
import NotchProtocol
import NotchRenderer

/// Another live activity in the wings: its leading content in a small circle,
/// ringed by its progress when it has one, so it is recognizable by its icon
/// and color. A click opens it.
struct MinimalCircle: View {
    let item: HostedSurface
    let accent: NotchTheme.Accent?
    static let diameter: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let leading = item.surface.compact?.leading.first
        // A ring already draws its own progress.
        let progress = leading?.type == .ring ? nil : Self.progress(in: item.surface.compact)
        let colors = NotchTheme.progressGradient(.accent, accent: accent)
        ZStack {
            Circle().fill(.white.opacity(0.08))
            if let leading {
                NativeNodeView(node: leading, compact: true) { _, _ in }
                    .scaleEffect(leading.type == .ring ? 0.8 : 0.62)
                    .clipShape(Circle())
            }
            if let progress {
                Circle().stroke(.white.opacity(0.16), lineWidth: 2)
                Circle().trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: colors, center: .center, startAngle: .zero,
                                            endAngle: .degrees(360 * max(progress, 0.01))),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : NotchTheme.valueChange, value: progress)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .fixedSize()
        .environment(\.notchAccent, accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.surface.title)
        .accessibilityAddTraits(.isButton)
        .help(item.surface.title)
    }

    /// The first progress or ring value anywhere in the wings.
    static func progress(in compact: CompactContent?) -> Double? {
        func find(_ node: UINode) -> Double? {
            if [.progress, .ring].contains(node.type), let value = node.props.value { return value }
            return node.children.lazy.compactMap(find).first
        }
        return ((compact?.leading ?? []) + (compact?.trailing ?? [])).lazy.compactMap(find).first
    }
}

/// More live activities than the wings have room for.
struct OverflowPill: View {
    let count: Int
    var body: some View {
        Text("+\(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 5).frame(height: 16)
            .background(.white.opacity(0.14), in: Capsule())
            .contentTransition(.numericText())
            .fixedSize()
            .accessibilityLabel("\(count) more live activities")
    }
}

/// Every activity in one grid: live ones first as wide tiles, then the rest.
/// It never scrolls: `HomeLayout.arrange` widens it, and past six columns the
/// last cell is a More tile that shows every activity as a compact chip.
struct HomeView: View {
    let tiles: [HostedSurface]
    let arrangement: HomeArrangement
    /// The tile the arrow keys are on.
    let focus: Int?
    @Binding var showsAll: Bool
    let accent: (HostedSurface) -> NotchTheme.Accent?
    let onOpen: (SurfaceKey) -> Void
    let onManage: () -> Void
    let onEditHome: () -> Void
    /// Reports a tile's natural content width, so a small tile too narrow for it becomes wide.
    let onMeasure: (SurfaceKey, CGFloat) -> Void
    /// The user's pins and sizes, for the tiles' menus.
    let preferences: HomePreferences
    let files: (String) -> NotchFiles?
    let onEdit: (SurfaceKey, HomeEdit) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.84) }
    private var gridWidth: CGFloat { arrangement.width - 2 * HomeLayout.padding }

    var body: some View {
        Group {
            if tiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No activities.").font(.system(size: 17, weight: .semibold))
                    Text("Your notch stays out of the way until an activity starts.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Open Settings & Extensions", action: onManage)
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                }
                .frame(width: gridWidth, alignment: .leading)
            } else if showsAll && arrangement.hiddenCount > 0 {
                allActivities
            } else {
                grid
            }
        }
        .onChange(of: arrangement.hiddenCount) { _, hidden in if hidden == 0 { showsAll = false } }
    }

    private var grid: some View {
        let cell = HomeLayout.cellWidth, spacing = HomeLayout.spacing
        let shown = arrangement.hiddenCount > 0 ? arrangement.placements.count - 1 : arrangement.placements.count
        return ZStack(alignment: .topLeading) {
            ForEach(Array(tiles.prefix(shown).enumerated()), id: \.element.key) { index, item in
                let place = arrangement.placements[index]
                HomeTile(item: item, accent: accent(item), focused: focus == index, onMeasure: { onMeasure(item.key, $0) }) { onOpen(item.key) }
                    .environment(\.notchFiles, files(item.key.extensionID))
                    .contextMenu { TileMenu(key: item.key, preferences: preferences, onEdit: onEdit, onEditHome: onEditHome) }
                    .frame(width: cell * CGFloat(place.span) + spacing * CGFloat(place.span - 1), height: HomeLayout.tileHeight)
                    .offset(x: CGFloat(place.column) * (cell + spacing), y: CGFloat(place.row) * (HomeLayout.tileHeight + spacing))
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            }
            if arrangement.hiddenCount > 0, let place = arrangement.placements.last {
                MoreTile(count: arrangement.hiddenCount, focused: focus == arrangement.placements.count - 1) { withAnimation(spring) { showsAll = true } }
                    .frame(width: cell, height: HomeLayout.tileHeight)
                    .offset(x: CGFloat(place.column) * (cell + spacing), y: CGFloat(place.row) * (HomeLayout.tileHeight + spacing))
            }
        }
        .frame(width: gridWidth, height: arrangement.height, alignment: .topLeading)
        .animation(spring, value: arrangement)
        .animation(spring, value: tiles.map(\.key.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Home")
    }

    /// Every activity as a one-line chip, in the same space as the grid.
    private var allActivities: some View {
        let columns = max(2, arrangement.columns - 2)
        return VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(tiles.prefix(columns * 5)) { item in
                    Button { onOpen(item.key) } label: {
                        HStack(spacing: 6) {
                            if let leading = item.surface.compact?.leading.first {
                                NativeNodeView(node: leading, compact: true) { _, _ in }.frame(width: 16, height: 16).clipped()
                            }
                            Text(item.surface.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9).frame(height: 28)
                        .background(.white.opacity(0.07), in: Capsule())
                        .contentShape(Capsule())
                        .environment(\.notchAccent, accent(item))
                    }
                    .buttonStyle(TilePressStyle())
                    .accessibilityLabel(item.surface.title)
                }
            }
            Spacer(minLength: 0)
            Button { withAnimation(spring) { showsAll = false } } label: {
                Label("Back to tiles", systemImage: "chevron.left").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .frame(width: gridWidth, height: arrangement.height, alignment: .topLeading)
        .transition(.opacity)
    }
}

/// What a tile's menu changes.
enum HomeEdit { case size(TileSize?), pin(Bool), hide }

/// A tile's right-click menu. Order and hidden tiles live in Settings, where
/// a hidden tile can come back.
private struct TileMenu: View {
    let key: SurfaceKey
    let preferences: HomePreferences
    let onEdit: (SurfaceKey, HomeEdit) -> Void
    let onEditHome: () -> Void
    var body: some View {
        Picker("Size", selection: Binding(get: { preferences.sizes[key.id] }, set: { onEdit(key, .size($0)) })) {
            Text("Automatic").tag(TileSize?.none)
            Text("Small").tag(TileSize?.some(.small))
            Text("Wide").tag(TileSize?.some(.wide))
        }
        let pinned = preferences.pinned.contains(key.id)
        Button(pinned ? "Unpin" : "Pin to Top") { onEdit(key, .pin(!pinned)) }
        Button("Hide from Home") { onEdit(key, .hide) }
        Divider()
        Button("Edit Home…", action: onEditHome)
    }
}

/// Opens every activity when Home has more than six columns can hold.
private struct MoreTile: View {
    let count: Int
    let focused: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("+\(count)").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer(minLength: 0)
                Text("More").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(focused ? 0.12 : 0.07)))
            .overlay(FocusRing(visible: focused))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .accessibilityLabel("\(count) more activities")
    }
}

/// One activity in Home. The extension's Tile when it has one, else its wings'
/// content with the title underneath. One type scale everywhere: text never
/// shrinks to fit, it ends with an ellipsis, and the app makes a tile wide
/// when its content needs it.
struct HomeTile: View {
    let item: HostedSurface
    let accent: NotchTheme.Accent?
    let focused: Bool
    let onMeasure: (CGFloat) -> Void
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                // An extension's own tile says what it is; one built from the wings needs the title.
                if item.surface.tile == nil {
                    Spacer(minLength: 0)
                    Text(item.surface.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, HomeTile.inset).padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: item.surface.tile == nil ? .topLeading : .leading)
            .clipped()
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(hovered || focused ? 0.12 : 0.07)))
            .overlay(FocusRing(visible: focused))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .environment(\.notchAccent, accent)
            .environment(\.notchTile, item.surface.tile != nil)
            .environment(\.notchTileOpen, { [action] in action() })
        }
        .buttonStyle(TilePressStyle())
        .background {
            // The content at its natural size, whatever room it has now.
            HStack(spacing: 8) { content }.fixedSize().hidden()
                .environment(\.notchTile, item.surface.tile != nil)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onMeasure($0) }
        }
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovered = inside }
        }
        .accessibilityLabel(item.surface.title)
        .accessibilityHint("Opens \(item.surface.title)")
        .help(item.surface.title)
    }

    static let inset: CGFloat = 10

    @ViewBuilder private var content: some View {
        if let tile = item.surface.tile {
            ForEach(tile.content) { NativeNodeView(node: $0, compact: true) { _, _ in } }
        } else if let compact = item.surface.compact {
            ForEach(compact.leading) { NativeNodeView(node: $0, compact: true) { _, _ in } }
            Spacer(minLength: 4)
            ForEach(compact.trailing) { NativeNodeView(node: $0, compact: true) { _, _ in } }
        }
    }
}

/// The arrow keys' tile: a soft outline that fades between tiles.
private struct FocusRing: View {
    let visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(visible ? 0.45 : 0), lineWidth: 1.5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: visible)
            .allowsHitTesting(false)
    }
}

private struct TilePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
