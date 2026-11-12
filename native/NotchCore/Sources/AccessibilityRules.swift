import Foundation

/// Pure accessibility rules for the notch, testable without SwiftUI.
public enum AccessibilityRules {
    /// Words in SF Symbol names that describe the drawing, not the meaning.
    private static let styleWords: Set<String> = [
        "fill", "circle", "square", "rectangle", "badge", "slash", "inset", "filled", "dashed", "app",
    ]

    /// A spoken name for an icon-only button whose extension gave no `label`,
    /// as extensions built before labels did: "stop.fill" → "Stop",
    /// "arrow.clockwise" → "Arrow clockwise", "bubble.left" → "Bubble left".
    public static func spokenName(forSymbol symbol: String) -> String {
        let words = symbol.split(separator: ".").map(String.init)
        let meaningful = words.filter { !styleWords.contains($0) }
        let chosen = (meaningful.isEmpty ? Array(words.prefix(1)) : meaningful).joined(separator: " ")
        return chosen.prefix(1).uppercased() + chosen.dropFirst()
    }

    /// The WCAG contrast ratio of two sRGB colors given as 0–1 components.
    public static func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        func luminance(_ color: (Double, Double, Double)) -> Double {
            func channel(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(color.0) + 0.7152 * channel(color.1) + 0.0722 * channel(color.2)
        }
        let (light, dark) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (light + 0.05) / (dark + 0.05)
    }

    /// White at `opacity` over gray `background`, as the notch composites it.
    public static func white(_ opacity: Double, over background: Double = 0) -> (Double, Double, Double) {
        let value = background + (1 - background) * opacity
        return (value, value, value)
    }

    /// White opacities on the black notch. Text inks meet WCAG AA (4.5:1) even
    /// over the strongest fill; Increase Contrast raises every one of them.
    public struct Inks: Sendable {
        public var primary, secondary, tertiary, separator, fill, fillStrong: Double
        public static let standard = Inks(primary: 0.94, secondary: 0.58, tertiary: 0.48, separator: 0.12, fill: 0.07, fillStrong: 0.12)
        public static let increased = Inks(primary: 1, secondary: 0.8, tertiary: 0.68, separator: 0.35, fill: 0.12, fillStrong: 0.18)
    }
    public static let success = (0.48, 0.85, 0.62), warning = (1.0, 0.74, 0.38), danger = (1.0, 0.45, 0.43)

    /// The shades behind a manifest's `accent` names. Each is light enough to
    /// read on black and to carry black text, as on an accent button.
    public static let accents: [String: (Double, Double, Double)] = [
        "orange": (1.0, 0.62, 0.30),
        "yellow": (1.0, 0.82, 0.32),
        "green": (0.45, 0.86, 0.55),
        "mint": (0.40, 0.88, 0.80),
        "cyan": (0.38, 0.80, 0.98),
        "blue": (0.47, 0.65, 1.0),
        "purple": (0.70, 0.58, 1.0),
        "pink": (1.0, 0.52, 0.72),
        "red": (1.0, 0.45, 0.43),
    ]

    /// Where an accent's progress gradient starts: a neighboring hue, so a
    /// bar reads green to yellow or blue to cyan as it fills. Shapes need 3:1.
    public static let accentGradientStarts: [String: (Double, Double, Double)] = [
        "orange": (1.0, 0.40, 0.36),
        "yellow": (0.52, 0.86, 0.45),
        "green": (0.34, 0.80, 0.76),
        "mint": (0.38, 0.70, 0.98),
        "cyan": (0.45, 0.52, 1.0),
        "blue": (0.64, 0.50, 1.0),
        "purple": (0.45, 0.56, 1.0),
        "pink": (0.74, 0.50, 1.0),
        "red": (1.0, 0.60, 0.30),
    ]
}
