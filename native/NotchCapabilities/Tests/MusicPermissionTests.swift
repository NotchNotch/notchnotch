import Carbon
import Testing
@testable import NotchCapabilities

@Test func everyMacOSAnswerToAutomationMapsToAnOutcome() {
    #expect(AutomationPermission(status: noErr) == .granted)
    #expect(AutomationPermission(status: OSStatus(errAEEventNotPermitted)) == .denied)
    #expect(AutomationPermission(status: OSStatus(procNotFound)) == .playerNotRunning)
    #expect(AutomationPermission(status: OSStatus(errAEEventWouldRequireUserConsent)) == .needsConsent)
    #expect(AutomationPermission(status: nil) == .noAnswer)
    #expect(AutomationPermission(status: -50) == .failed(-50))
}

@Test func connectSaysWhatToDoWhenAccessIsNotGranted() {
    #expect(AutomationPermission.granted.problem(for: .spotify, appID: "dev.notchnotch.app") == nil)
    #expect(AutomationPermission.playerNotRunning.problem(for: .spotify, appID: "dev.notchnotch.app") == "Open Spotify, then connect again")
    // A stuck request names the reset for this app's own identifier, so a dev build gets its own.
    let stuck = AutomationPermission.noAnswer.problem(for: .spotify, appID: "dev.notchnotch.app.dev") ?? ""
    #expect(stuck.contains("tccutil reset AppleEvents dev.notchnotch.app.dev"))
    #expect(AutomationPermission.denied.problem(for: .music, appID: "dev.notchnotch.app")?.contains("Automation") == true)
}
