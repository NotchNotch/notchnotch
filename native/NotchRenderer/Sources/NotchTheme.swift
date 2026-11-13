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

    /// An extension's color and the neighboring hue its progress gradients start from.
    public struct Accent: Equatable, Sendable {
        public let color: Color
        public let gradientStart: Color
    }

    /// The shades for a manifest's `accent`; nil for no accent or a name this app doesn't know.
    public static func accent(named name: String?) -> Accent? {
        guard let name, let color = AccessibilityRules.accents[name],
              let start = AccessibilityRules.accentGradientStarts[name] else { return nil }
        return Accent(color: rgb(color), gradientStart: rgb(start))
    }

    /// A progress fill: the accent's two hues, or a tone fading in from dim.
    public static func progressGradient(_ tone: Tone?, accent: Accent?) -> [Color] {
        if tone == .accent || tone == nil, let accent { return [accent.gradientStart, accent.color] }
        let color = color(tone ?? .accent)
        return [color.opacity(0.7), color]
    }
    public static let progressHeight: CGFloat = 8

    /// `accent` is the extension's color from the environment; without one, accents are white.
    public static func color(_ tone: Tone?, accent: Color? = nil) -> Color {
        switch tone {
        case .secondary: Ink.secondary
        case .success: success
        case .warning: warning
        case .danger: danger
        case .accent: accent ?? Ink.primary
        case .primary, nil: Ink.primary
        }
    }

    // MARK: Motion
    /// Short readings such as "17:38", "$2,046" or "82 mmhg" roll digit by
    /// digit when they change; sentences just change.
    public static func rollsDigits(_ text: String) -> Bool {
        text.count <= 24 && text.contains(where: \.isNumber)
    }
    public static let valueChange = Animation.snappy(duration: 0.35)

    // MARK: Typography
    public static func font(_ size: TextSize?, compact: Bool = false, tile: Bool = false) -> Font {
        // Home tiles: one fixed scale between the wings and the open notch,
        // so a tile reads at a glance and never shrinks to fit.
        if tile {
            switch size {
            case .caption: return .system(size: 11, weight: .semibold)
            case .body, nil: return .system(size: 13, weight: .regular)
            case .headline: return .system(size: 14, weight: .semibold)
            case .title, .timer: return .system(size: 22, weight: .semibold, design: .rounded)
            }
        }
        // Wing readings: rounded like the system's own live activities, and
        // sized to sit centered in the 32 pt bar beside the camera.
        if compact {
            return .system(size: size == .caption ? 12 : 13, weight: .semibold, design: .rounded)
        }
        switch size {
        case .caption: return .system(size: 11, weight: .semibold)
        case .headline: return .system(size: 14, weight: .semibold)
        case .title: return .system(size: 19, weight: .semibold)
        case .timer: return .system(size: 34, weight: .light, design: .rounded)
        case .body, nil: return .system(size: 13, weight: .regular)
        }
    }
    /// A Value's unit: about half its number, so the reading leads.
    public static func unitFont(_ size: TextSize?, compact: Bool = false, tile: Bool = false) -> Font {
        if tile { return .system(size: 11, weight: .semibold) }
        if compact { return .system(size: 10, weight: .semibold) }
        switch size {
        case .timer: return .system(size: 15, weight: .semibold)
        case .title: return .system(size: 12, weight: .semibold)
        case .headline, .body, .caption, nil: return .system(size: 11, weight: .semibold)
        }
    }
    /// A Ring's diameter along the text scale; compact wings hold a small one.
    public static func ringDiameter(_ size: TextSize?, compact: Bool = false, tile: Bool = false) -> CGFloat {
        if tile { return 30 }
        if compact { return 13 }
        switch size {
        case .caption: return 16
        case .body: return 22
        case .headline, nil: return 30
        case .title: return 44
        case .timer: return 64
        }
    }
    public static func tracking(_ size: TextSize?, compact: Bool = false, tile: Bool = false) -> CGFloat {
        if tile { return size == .title || size == .timer ? -0.3 : 0 }
        return switch size {
        case .caption: compact ? 0 : 0.4
        case .timer: -0.8
        case .title: -0.2
        default: 0
        }
    }
    public static func symbolSize(_ size: TextSize?, compact: Bool = false, tile: Bool = false) -> CGFloat {
        if tile { return 14 }
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

extension EnvironmentValues {
    /// The shown extension's accent shade, set by the host from its manifest.
    @Entry public var notchAccent: NotchTheme.Accent? = nil
    /// Drawing inside a Home tile: one line per text, mid-sized artwork.
    @Entry public var notchTile = false
    /// Opens the tile's activity: a tile's drag source takes the click, so it passes it on.
    @Entry public var notchTileOpen: (@MainActor () -> Void)? = nil
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
