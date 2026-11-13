import SwiftUI
import NotchProtocol

/// A number with its unit beside it on one baseline: "45" large in the
/// extension's color, "min" small and gray. Digits roll when it changes.
struct NotchValue: View {
    let node: UINode
    let compact: Bool
    @Environment(\.notchAccent) private var accent
    @Environment(\.notchTile) private var tile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = node.props.text ?? ""
        let size = node.props.size ?? .timer
        HStack(alignment: .firstTextBaseline, spacing: compact ? 2 : 4) {
            Text(text)
                .font(NotchTheme.font(size, compact: compact, tile: tile))
                .tracking(NotchTheme.tracking(size, compact: compact, tile: tile))
                .monospacedDigit()
                .foregroundStyle(NotchTheme.color(node.props.tone ?? .accent, accent: accent?.color))
                .contentTransition(NotchTheme.rollsDigits(text) && !reduceMotion ? .numericText() : .identity)
                .animation(reduceMotion ? nil : NotchTheme.valueChange, value: text)
            if let unit = node.props.unit, !unit.isEmpty {
                Text(unit)
                    .font(NotchTheme.unitFont(size, compact: compact, tile: tile))
                    .foregroundStyle(NotchTheme.Ink.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text, node.props.unit ?? ""].filter { !$0.isEmpty }.joined(separator: " "))
    }
}

/// Circular progress with the same gradient as a progress bar, from the
/// neighboring hue at twelve o'clock into the extension's color at the tip.
/// Children are drawn in the middle.
struct NotchRing: View {
    let node: UINode
    let compact: Bool
    let cameraHeight: CGFloat
    let onEvent: (String, String?) -> Void
    @Environment(\.notchAccent) private var accent
    @Environment(\.notchTile) private var tile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let diameter = NotchTheme.ringDiameter(node.props.size, compact: compact, tile: tile)
        let line = max(2.5, (diameter * 0.15).rounded())
        let value = node.props.value ?? 0
        let colors = NotchTheme.progressGradient(node.props.tone, accent: accent)
        ZStack {
            Circle().stroke(NotchTheme.Ink.fillStrong, lineWidth: line)
            Circle()
                .trim(from: 0, to: value)
                .stroke(AngularGradient(colors: colors, center: .center,
                                        startAngle: .zero, endAngle: .degrees(360 * max(value, 0.01))),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : NotchTheme.valueChange, value: value)
            // The round cap at the start would sample the gradient's far end;
            // paint it in the start color instead.
            Circle().fill(colors[0]).frame(width: line, height: line)
                .offset(y: -diameter / 2)
                .opacity(value > 0 ? 1 : 0)
            ForEach(node.children) {
                NativeNodeView(node: $0, compact: compact, cameraHeight: cameraHeight, onEvent: onEvent)
            }
        }
        .padding(line / 2)
        .frame(width: diameter + line, height: diameter + line)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.props.label ?? "Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
