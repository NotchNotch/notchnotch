import SwiftUI
import NotchProtocol

struct SettingsActionButton: View {
    let node: UINode
    let onEvent: (String, String?) -> Void
    var body: some View {
        Group {
            if node.props.tone == .accent {
                Button(action: send) { label }.buttonStyle(.borderedProminent)
            } else {
                Button(action: send) { label }.buttonStyle(.bordered).tint(node.props.tone == .danger ? .red : nil)
            }
        }.controlSize(.regular).disabled(node.props.disabled ?? false)
    }
    @ViewBuilder private var label: some View {
        if let symbol = node.props.name {
            if let title = node.props.text, !title.isEmpty {
                Label(title, systemImage: symbol)
            } else {
                Image(systemName: symbol).accessibilityLabel(symbol)
            }
        } else { Text(node.props.text ?? "") }
    }
    private func send() { if let action = node.props.action { onEvent(action, nil) } }
}
