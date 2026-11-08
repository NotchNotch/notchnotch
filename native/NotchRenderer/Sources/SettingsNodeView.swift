import SwiftUI
import NotchProtocol

/// The management-window presentation of the same validated extension UI tree.
/// System colors and native controls keep setup readable in both appearances.
/// Root-level `section` nodes are lifted into real form sections by the host;
/// nested sections render as a titled group.
public struct SettingsNodeView: View {
    public let node: UINode
    public let onEvent: (String, String?) -> Void
    public init(node: UINode, onEvent: @escaping (String, String?) -> Void) {
        self.node = node; self.onEvent = onEvent
    }
    public var body: some View { content }

    private var children: some View {
        ForEach(node.children) { SettingsNodeView(node: $0, onEvent: onEvent) }
    }

    @ViewBuilder private var content: some View {
        switch node.type {
        case .column:
            let align = node.props.align ?? .start
            VStack(alignment: align.horizontal, spacing: Self.spacing(node.props.spacing, fallback: 12)) { children }
                .frame(maxWidth: .infinity, alignment: align.frame)
        case .row:
            let spacing = Self.spacing(node.props.spacing, fallback: 10)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: (node.props.align ?? .center).vertical, spacing: spacing) { children }.fixedSize()
                VStack(alignment: .leading, spacing: spacing) { children }
            }
        case .text:
            Text(node.props.text ?? "").font(Self.font(node.props.size))
                .foregroundStyle(Self.color(node.props.tone)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        case .symbol:
            Image(systemName: node.props.name ?? "circle").foregroundStyle(Self.color(node.props.tone))
        case .progress:
            ProgressView(value: node.props.value ?? 0)
        case .button:
            SettingsActionButton(node: node, onEvent: onEvent)
        case .textField:
            SettingsTextField(node: node, onEvent: onEvent)
        case .spacer:
            Spacer(minLength: 0)
        case .divider:
            Divider()
        case .toggle:
            Toggle(node.props.text ?? "", isOn: Binding(
                get: { node.props.value == 1 },
                set: { value in if let action = node.props.action { onEvent(action, value ? "true" : "false") } }))
                .toggleStyle(.switch)
                .disabled(node.props.disabled ?? false)
        case .badge:
            Text(node.props.text ?? "").font(.caption.weight(.medium)).monospacedDigit()
                .padding(.horizontal, 7).padding(.vertical, 2)
                .foregroundStyle(Self.color(node.props.tone ?? .secondary))
                .background(Self.color(node.props.tone ?? .secondary).opacity(0.14), in: Capsule())
        case .section:
            VStack(alignment: .leading, spacing: 8) {
                if let title = node.props.text, !title.isEmpty { Text(title).font(.headline) }
                children
                if let footer = node.props.detail, !footer.isEmpty {
                    Text(footer).font(.callout).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        case .picker:
            Picker(node.props.text ?? "", selection: Binding(
                get: { node.props.selection ?? "" },
                set: { value in if let action = node.props.action { onEvent(action, value) } })) {
                if node.props.selection == nil { Text("Choose…").tag("") }
                ForEach(node.props.options ?? [], id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.menu)
            .labelsHidden(node.props.text?.isEmpty ?? true)
            .disabled(node.props.disabled ?? false)
        case .listItem:
            SettingsListItem(node: node, onEvent: onEvent)
        case .artwork, .waveform, .player:
            EmptyView() // Excluded by the settings contract before rendering.
        }
    }

    static func spacing(_ spacing: Spacing?, fallback: CGFloat) -> CGFloat {
        guard let spacing else { return fallback }
        switch spacing {
        case .none: return 0
        case .tight: return 4
        case .regular: return 8
        case .loose: return 16
        }
    }
    static func font(_ size: TextSize?) -> Font {
        switch size {
        case .caption: .caption
        case .headline: .headline
        case .title: .title3.weight(.semibold)
        case .timer: .system(.title, design: .rounded).weight(.light)
        case .body, nil: .body
        }
    }
    static func color(_ tone: Tone?) -> Color {
        switch tone {
        case .secondary: .secondary
        case .accent: .accentColor
        case .success: .green
        case .warning: .orange
        case .danger: .red
        case .primary, nil: .primary
        }
    }
}

private struct SettingsListItem: View {
    let node: UINode
    let onEvent: (String, String?) -> Void
    var body: some View {
        let row = LabeledContent {
            HStack(spacing: 8) {
                ForEach(node.children) { SettingsNodeView(node: $0, onEvent: onEvent) }
            }
        } label: {
            Label {
                Text(node.props.text ?? "")
                if let detail = node.props.detail, !detail.isEmpty { Text(detail) }
            } icon: {
                if let symbol = node.props.name {
                    Image(systemName: symbol).foregroundStyle(SettingsNodeView.color(node.props.tone ?? .accent))
                }
            }
        }
        if let action = node.props.action {
            Button { onEvent(action, nil) } label: { row.contentShape(Rectangle()) }
                .buttonStyle(.plain).disabled(node.props.disabled ?? false)
        } else { row }
    }
}

private extension View {
    @ViewBuilder func labelsHidden(_ hidden: Bool) -> some View {
        if hidden { labelsHidden() } else { self }
    }
}
