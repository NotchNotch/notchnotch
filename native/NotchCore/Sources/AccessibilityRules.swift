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
}
