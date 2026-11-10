import AppKit
import NotchCore

/// System state and VoiceOver output for the notch. The rules themselves are
/// in `AccessibilityRules`.
public enum NotchAccessibility {
    /// Whether macOS's Increase Contrast setting is on.
    public static var increasesContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

    /// Reads `text` aloud with VoiceOver when it's running, without moving focus.
    /// The notch's announcements (Peek) are otherwise only visible.
    @MainActor public static func announce(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled, !text.isEmpty, let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
