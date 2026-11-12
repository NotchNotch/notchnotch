import Testing
@testable import NotchCore
import NotchProtocol

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

@Test func everyAccentReadsOnTheNotchAndUnderBlackText() {
    #expect(Set(AccessibilityRules.accents.keys) == Set(AccentColor.all))
    for (name, hue) in AccessibilityRules.accents {
        // Accent text and progress sit on black or a section's fill; an accent button carries black text.
        for background in [0, AccessibilityRules.Inks.standard.fill] {
            let ratio = AccessibilityRules.contrast(hue, AccessibilityRules.white(0, over: background))
            #expect(ratio >= 4.5, "\(name) over \(background): \(ratio)")
        }
        #expect(AccessibilityRules.contrast(hue, (0, 0, 0)) >= 4.5, "black on \(name)")
    }
    #expect(Set(AccessibilityRules.accentGradientStarts.keys) == Set(AccentColor.all))
    for (name, start) in AccessibilityRules.accentGradientStarts {
        // A progress bar's start sits beside its track (white at fillStrong over black).
        let track = AccessibilityRules.white(AccessibilityRules.Inks.standard.fillStrong)
        #expect(AccessibilityRules.contrast(start, track) >= 3, "\(name) gradient start against the track")
    }
}

@Test func theOldTertiaryInkWouldHaveFailed() {
    // 0.36 was the tertiary ink before this check existed.
    #expect(AccessibilityRules.contrast(AccessibilityRules.white(0.36, over: 0.12), AccessibilityRules.white(0, over: 0.12)) < 4.5)
}
