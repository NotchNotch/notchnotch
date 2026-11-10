import SwiftUI
import NotchProtocol
import NotchCore

/// Design tokens for everything drawn inside the notch. The notch is always a
/// black surface, so colors are expressed as white opacities plus a few
/// semantic hues. Extensions choose semantic values (tone, size, spacing);
/// the host owns the actual metrics.
public enum NotchTheme {
    // MARK: Color
    static var inks: AccessibilityRules.Inks { NotchAccessibility.increasesContrast ? .increased : .standard }
    public enum Ink {
        public static var primary: Color { .white.opacity(inks.primary) }
        public static var secondary: Color { .white.opacity(inks.secondary) }
        public static var tertiary: Color { .white.opacity(inks.tertiary) }
        public static var separator: Color { .white.opacity(inks.separator) }
        public static var fill: Color { .white.opacity(inks.fill) }
        public static var fillStrong: Color { .white.opacity(inks.fillStrong) }
    }
    public static let success = rgb(AccessibilityRules.success)
    public static let warning = rgb(AccessibilityRules.warning)
    public static let danger = rgb(AccessibilityRules.danger)
    private static func rgb(_ value: (Double, Double, Double)) -> Color { Color(red: value.0, green: value.1, blue: value.2) }

    public static func color(_ tone: Tone?) -> Color {
        switch tone {
        case .secondary: Ink.secondary
        case .success: success
        case .warning: warning
        case .danger: danger
        case .accent, .primary, nil: Ink.primary
        }
    }

    // MARK: Typography
    public static func font(_ size: TextSize?, compact: Bool = false) -> Font {
        if compact {
            return size == .caption ? .system(size: 11, weight: .semibold) : .system(size: 12, weight: .semibold)
        }
        switch size {
        case .caption: return .system(size: 11, weight: .semibold)
        case .headline: return .system(size: 14, weight: .semibold)
        case .title: return .system(size: 19, weight: .semibold)
        case .timer: return .system(size: 34, weight: .light, design: .rounded)
        case .body, nil: return .system(size: 13, weight: .regular)
        }
    }
    public static func tracking(_ size: TextSize?, compact: Bool = false) -> CGFloat {
        switch size {
        case .caption: compact ? 0 : 0.4
        case .timer: -0.8
        case .title: -0.2
        default: 0
        }
    }
    public static func symbolSize(_ size: TextSize?, compact: Bool = false) -> CGFloat {
        if compact { return 13 }
        switch size {
        case .caption: return 11
        case .headline: return 16
        case .title: return 20
        case .timer: return 28
        case .body, nil: return 14
        }
    }

    // MARK: Layout
    public static func spacing(_ spacing: Spacing?, compact: Bool = false, fallback: Spacing = .regular) -> CGFloat {
        switch spacing ?? fallback {
        case .none: 0
        case .tight: compact ? 3 : 4
        case .regular: compact ? 6 : 8
        case .loose: compact ? 10 : 14
        }
    }
    public static let controlHeight: CGFloat = 28
    public static let controlRadius: CGFloat = 9
    public static let groupRadius: CGFloat = 12
    public static let iconTile: CGFloat = 26
}

extension LayoutAlignment {
    var horizontal: HorizontalAlignment {
        switch self { case .start: .leading; case .center: .center; case .end: .trailing }
    }
    var vertical: VerticalAlignment {
        switch self { case .start: .top; case .center: .center; case .end: .bottom }
    }
    var frame: SwiftUI.Alignment {
        switch self { case .start: .leading; case .center: .center; case .end: .trailing }
    }
}
