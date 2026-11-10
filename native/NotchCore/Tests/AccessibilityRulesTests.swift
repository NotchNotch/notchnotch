import Testing
@testable import NotchCore

@Test func iconOnlyButtonsWithoutALabelGetASpokenName() {
    #expect(AccessibilityRules.spokenName(forSymbol: "stop.fill") == "Stop")
    #expect(AccessibilityRules.spokenName(forSymbol: "arrow.clockwise") == "Arrow clockwise")
    #expect(AccessibilityRules.spokenName(forSymbol: "xmark.circle.fill") == "Xmark")
    #expect(AccessibilityRules.spokenName(forSymbol: "arrow.up.forward.app") == "Arrow up forward")
    #expect(AccessibilityRules.spokenName(forSymbol: "circle.fill") == "Circle")
}

@Test func notchTextMeetsWCAGAAInBothContrastModes() {
    for (mode, ink) in [("standard", AccessibilityRules.Inks.standard), ("increased", AccessibilityRules.Inks.increased)] {
        // Text sits on black, on a section's fill or on an icon tile's stronger fill.
        for background in [0, ink.fill, ink.fillStrong] {
            for (name, opacity) in [("primary", ink.primary), ("secondary", ink.secondary), ("tertiary", ink.tertiary)] {
                let ratio = AccessibilityRules.contrast(AccessibilityRules.white(opacity, over: background), AccessibilityRules.white(0, over: background))
                #expect(ratio >= 4.5, "\(mode) \(name) over \(background): \(ratio)")
            }
            for (name, hue) in [("success", AccessibilityRules.success), ("warning", AccessibilityRules.warning), ("danger", AccessibilityRules.danger)] {
                let ratio = AccessibilityRules.contrast(hue, AccessibilityRules.white(0, over: background))
                #expect(ratio >= 4.5, "\(mode) \(name) over \(background): \(ratio)")
            }
        }
    }
    #expect(AccessibilityRules.Inks.increased.tertiary > AccessibilityRules.Inks.standard.tertiary)
}

@Test func theOldTertiaryInkWouldHaveFailed() {
    // 0.36 was the tertiary ink before this check existed.
    #expect(AccessibilityRules.contrast(AccessibilityRules.white(0.36, over: 0.12), AccessibilityRules.white(0, over: 0.12)) < 4.5)
}
