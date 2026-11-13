import SwiftUI
import NotchCore
import NotchProtocol

/// Renders an extension UI tree inside the notch using `NotchTheme` tokens.
public struct NativeNodeView: View {
    public let node: UINode
    public let compact: Bool
    public let cameraHeight: CGFloat
    public let onEvent: (String, String?) -> Void
    public init(node: UINode, compact: Bool = false, cameraHeight: CGFloat = 32, onEvent: @escaping (String, String?) -> Void) {
        self.node = node; self.compact = compact; self.cameraHeight = cameraHeight; self.onEvent = onEvent
    }

    /// Read so the tree redraws when Increase Contrast changes; the inks follow it.
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.notchAccent) private var accent
    @Environment(\.notchTile) private var tile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        content.foregroundStyle(NotchTheme.color(tone, accent: accent?.color))
    }

    /// In the wings an icon in the default tone takes the extension's color,
    /// so an activity is recognizable at a glance beside the camera.
    private var tone: Tone? {
        guard compact, node.type == .symbol, node.props.tone == nil || node.props.tone == .primary else { return node.props.tone }
        return .accent
    }

    private var valueChange: Animation? { reduceMotion ? nil : NotchTheme.valueChange }

    private func child(_ node: UINode) -> NativeNodeView {
        NativeNodeView(node: node, compact: compact, cameraHeight: cameraHeight, onEvent: onEvent)
    }
    private var children: some View { ForEach(node.children) { child($0) } }

    @ViewBuilder private var content: some View {
        switch node.type {
        case .column:
            let align = node.props.align ?? .start
            VStack(alignment: align.horizontal, spacing: NotchTheme.spacing(node.props.spacing, compact: compact)) { children }
                .frame(maxWidth: compact && !tile ? nil : .infinity, alignment: align.frame)
        case .row:
            HStack(alignment: (node.props.align ?? .center).vertical,
                   spacing: NotchTheme.spacing(node.props.spacing, compact: compact, fallback: compact ? .regular : .loose)) { children }
        case .text:
            let text = node.props.text ?? ""
            Text(text)
                .font(NotchTheme.font(node.props.size, compact: compact, tile: tile))
                .monospacedDigit()
                .contentTransition(NotchTheme.rollsDigits(text) && !reduceMotion ? .numericText() : .identity)
                .animation(valueChange, value: text)
                .tracking(NotchTheme.tracking(node.props.size, compact: compact, tile: tile))
                .lineLimit(compact || tile ? 1 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(node.props.text ?? "")
        case .symbol:
            // Decorative unless the extension says what it means.
            Image(systemName: node.props.name ?? "circle")
                .font(.system(size: NotchTheme.symbolSize(node.props.size, compact: compact, tile: tile), weight: .medium))
                .accessibilityLabel(node.props.label ?? "")
                .accessibilityHidden(node.props.label?.isEmpty ?? true)
        case .progress:
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(NotchTheme.Ink.fillStrong)
                    // The gradient runs across the fill, so its leading tip is always
                    // the extension's own color. Untoned bars use the extension's color.
                    Capsule()
                        .fill(LinearGradient(colors: NotchTheme.progressGradient(node.props.tone, accent: accent),
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geometry.size.height, geometry.size.width * (node.props.value ?? 0)))
                        .opacity((node.props.value ?? 0) > 0 ? 1 : 0)
                }
                .animation(valueChange, value: node.props.value)
            }.frame(height: tile ? 5 : NotchTheme.progressHeight)
                .accessibilityElement()
                .accessibilityLabel(node.props.label ?? "Progress")
                .accessibilityValue("\(Int((node.props.value ?? 0) * 100)) percent")
        case .button:
            NotchButton(node: node, onEvent: onEvent)
        case .textField:
            NativeTextField(node: node, onEvent: onEvent)
        case .spacer:
            Spacer(minLength: 0)
        case .divider:
            Rectangle().fill(NotchTheme.Ink.separator).frame(height: 0.5)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
        case .toggle:
            NotchToggle(node: node, onEvent: onEvent)
        case .badge:
            Text(node.props.text ?? "")
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .padding(.horizontal, 7).frame(height: 18)
                .foregroundStyle(NotchTheme.color(node.props.tone ?? .secondary, accent: accent?.color))
                .background(NotchTheme.color(node.props.tone ?? .secondary, accent: accent?.color).opacity(0.16), in: Capsule())
                .fixedSize()
        case .section:
            VStack(alignment: .leading, spacing: 6) {
                if let title = node.props.text, !title.isEmpty {
                    Text(title.uppercased())
                        .font(NotchTheme.font(.caption)).tracking(NotchTheme.tracking(.caption))
                        .foregroundStyle(NotchTheme.Ink.tertiary)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: NotchTheme.spacing(node.props.spacing, fallback: .regular)) { children }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NotchTheme.Ink.fill, in: RoundedRectangle(cornerRadius: NotchTheme.groupRadius))
                if let footer = node.props.detail, !footer.isEmpty {
                    Text(footer).font(NotchTheme.font(.caption)).foregroundStyle(NotchTheme.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .picker:
            NotchSegmentedPicker(node: node, onEvent: onEvent)
        case .listItem:
            NotchListItem(node: node, compact: compact, cameraHeight: cameraHeight, onEvent: onEvent)
        case .unknown:
            // A component from a newer SDK: leave it out and draw the rest.
            EmptyView()
        case .value:
            NotchValue(node: node, compact: compact)
        case .fileItem:
            if let file = node.props.file?.file { NotchFileItem(file: file, compact: compact) }
        case .fileGrid:
            if let files = node.props.files?.files, !files.isEmpty {
                NotchFileGrid(files: files, selected: node.props.selected, removable: node.props.removable ?? false,
                              action: node.props.action, onEvent: onEvent)
            }
        case .ring:
            NotchRing(node: node, compact: compact, cameraHeight: cameraHeight, onEvent: onEvent)
        case .artwork:
            AlbumArtwork(source: node.props.source, size: tile ? 40 : compact ? 18 : 60)
        case .waveform:
            PlaybackWaveform(playing: node.props.value == 1, source: node.props.source)
        case .player:
            if let state = node.props.media {
                MusicPlayerView(state: state, cameraHeight: cameraHeight) { request in
                    guard let action = node.props.action,
                          let data = try? JSONEncoder().encode(request),
                          let value = String(data: data, encoding: .utf8) else { return }
                    onEvent(action, value)
                }
            }
        }
    }
}

struct NotchPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Accent is the single prominent action; danger is destructive; everything
/// else is a quiet filled capsule. An optional SF Symbol leads the title.
struct NotchButton: View {
    let node: UINode
    let onEvent: (String, String?) -> Void
    @Environment(\.notchAccent) private var accent
    private var foreground: Color {
        switch node.props.tone {
        case .accent: .black
        case .danger: NotchTheme.danger
        case .success: NotchTheme.success
        case .warning: NotchTheme.warning
        default: NotchTheme.Ink.primary
        }
    }
    private var background: Color {
        switch node.props.tone {
        case .accent: accent?.color ?? .white
        case .danger: NotchTheme.danger.opacity(0.16)
        default: NotchTheme.Ink.fillStrong
        }
    }
    var body: some View {
        let title = node.props.text ?? ""
        Button {
            if let action = node.props.action { onEvent(action, nil) }
        } label: {
            HStack(spacing: 5) {
                if let symbol = node.props.name {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                if !title.isEmpty { Text(title).lineLimit(1) }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, title.isEmpty ? 0 : 13)
            .frame(minWidth: NotchTheme.controlHeight, minHeight: NotchTheme.controlHeight)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NotchPressStyle())
        .disabled(node.props.disabled ?? false)
        .opacity(node.props.disabled == true ? 0.4 : 1)
        .accessibilityLabel(Self.label(for: node))
        .help(title.isEmpty ? Self.label(for: node) : "")
    }
    /// The extension's `label`, the title, or a name made from the symbol for older extensions.
    static func label(for node: UINode) -> String {
        if let label = node.props.label, !label.isEmpty { return label }
        if let title = node.props.text, !title.isEmpty { return title }
        return AccessibilityRules.spokenName(forSymbol: node.props.name ?? "Button")
    }
}

/// A compact switch drawn for a black surface; the system switch renders as
/// inactive inside a nonactivating panel.
private struct NotchToggle: View {
    let node: UINode
    let onEvent: (String, String?) -> Void
    @State private var isOn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button {
            guard let action = node.props.action else { return }
            isOn.toggle()
            onEvent(action, isOn ? "true" : "false")
        } label: {
            HStack(spacing: 10) {
                if let label = node.props.text, !label.isEmpty {
                    Text(label).font(NotchTheme.font(.body)).foregroundStyle(NotchTheme.Ink.primary)
                    Spacer(minLength: 0)
                }
                Capsule()
                    .fill(isOn ? NotchTheme.success : NotchTheme.Ink.fillStrong)
                    .frame(width: 30, height: 18)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                    }
                    .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: isOn)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(node.props.disabled ?? false)
        .opacity(node.props.disabled == true ? 0.4 : 1)
        .onAppear { isOn = node.props.value == 1 }
        .onChange(of: node.props.value) { _, value in isOn = value == 1 }
        .accessibilityRepresentation {
            Toggle(node.props.text ?? "", isOn: Binding(get: { isOn }, set: { _ in
                if let action = node.props.action { isOn.toggle(); onEvent(action, isOn ? "true" : "false") }
            }))
        }
    }
}

/// Segmented control drawn for the black notch surface. Selection is
/// optimistic so the highlight moves before the runner round-trip.
private struct NotchSegmentedPicker: View {
    let node: UINode
    let onEvent: (String, String?) -> Void
    @State private var selection: String?
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 10) {
            if let label = node.props.text, !label.isEmpty {
                Text(label).font(NotchTheme.font(.body)).foregroundStyle(NotchTheme.Ink.primary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 2) {
                ForEach(node.props.options ?? [], id: \.value) { option in
                    let selected = option.value == selection
                    Button {
                        guard let action = node.props.action, !selected else { return }
                        selection = option.value
                        onEvent(action, option.value)
                    } label: {
                        Text(option.label)
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                            .foregroundStyle(selected ? Color.black : NotchTheme.Ink.secondary)
                            .padding(.horizontal, 10).frame(height: 22)
                            .background {
                                if selected {
                                    Capsule().fill(.white).matchedGeometryEffect(id: "selection", in: highlight)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .background(NotchTheme.Ink.fillStrong, in: Capsule())
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: selection)
        }
        .disabled(node.props.disabled ?? false)
        .opacity(node.props.disabled == true ? 0.4 : 1)
        .onAppear { selection = node.props.selection }
        .onChange(of: node.props.selection) { _, value in selection = value }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(node.props.text ?? "Options")
    }
}

/// Icon tile, title, optional detail line, and trailing accessories (children).
/// With an action the whole row is one button.
private struct NotchListItem: View {
    let node: UINode
    let compact: Bool
    let cameraHeight: CGFloat
    let onEvent: (String, String?) -> Void
    @Environment(\.notchAccent) private var accent
    @Environment(\.notchFiles) private var files
    @ViewBuilder private var row: some View {
        if let drag = node.props.drag {
            content.onDrag {
                files?.draggingOut()
                if let url = URL(string: drag), ["http", "https"].contains(url.scheme?.lowercased()) {
                    return NSItemProvider(object: url as NSURL)
                }
                return NSItemProvider(object: drag as NSString)
            }
        } else {
            content
        }
    }
    private var content: some View {
        HStack(spacing: 10) {
            if let symbol = node.props.name {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NotchTheme.color(node.props.tone, accent: accent?.color))
                    .frame(width: NotchTheme.iconTile, height: NotchTheme.iconTile)
                    .background(NotchTheme.Ink.fillStrong, in: RoundedRectangle(cornerRadius: 7))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(node.props.text ?? "").font(NotchTheme.font(.body).weight(.medium))
                    .foregroundStyle(NotchTheme.Ink.primary).lineLimit(1)
                if let detail = node.props.detail, !detail.isEmpty {
                    Text(detail).font(NotchTheme.font(.caption).weight(.regular))
                        .foregroundStyle(NotchTheme.Ink.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            ForEach(node.children) {
                NativeNodeView(node: $0, compact: compact, cameraHeight: cameraHeight, onEvent: onEvent)
            }
            if node.props.action != nil {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.Ink.tertiary)
            }
        }
        .frame(minHeight: NotchTheme.iconTile)
        .contentShape(Rectangle())
    }
    var body: some View {
        if let action = node.props.action {
            Button { onEvent(action, nil) } label: { row }
                .buttonStyle(NotchPressStyle())
                .disabled(node.props.disabled ?? false)
        } else {
            row.accessibilityElement(children: .combine)
        }
    }
}

private struct NativeTextField: View {
    let node: UINode
    let onEvent: (String, String?) -> Void
    @State private var text = ""
    @FocusState private var isEditing: Bool
    var body: some View {
        TextField(node.props.placeholder ?? "", text: $text)
            .focused($isEditing)
            .textFieldStyle(.plain)
            .font(NotchTheme.font(.body))
            .padding(.horizontal, 10).frame(height: 32)
            .background(NotchTheme.Ink.fill, in: RoundedRectangle(cornerRadius: NotchTheme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: NotchTheme.controlRadius)
                .strokeBorder(isEditing ? NotchTheme.Ink.tertiary : NotchTheme.Ink.separator, lineWidth: 0.5))
            .disabled(node.props.disabled ?? false)
            .accessibilityLabel(node.props.label ?? node.props.placeholder ?? "Text")
            .onAppear { text = node.props.text ?? "" }
            .onChange(of: node.props.text) { _, value in
                // A runner acknowledgement can arrive several keystrokes behind.
                // Never replace an active native edit with an older React render.
                if !isEditing, text != value { text = value ?? "" }
            }
            .onChange(of: text) { _, value in
                if isEditing, value != node.props.text, let action = node.props.action {
                    onEvent(action, String(value.prefix(4096)))
                }
            }
    }
}
