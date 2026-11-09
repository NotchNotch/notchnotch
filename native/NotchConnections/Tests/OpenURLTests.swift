import Foundation
import Testing
import NotchProtocol

@Test func openAcceptsWebAddressesAndAppLinksOnly() throws {
    for url in ["https://example.com/page?q=1", "http://example.com", "mailto:someone@example.com", "zoommtg://zoom.us/join?confno=1", "spotify:track:1"] {
        #expect(throws: Never.self, "\(url)") { try OpenURLPolicy.validate(url) }
    }
    for url in ["file:///etc/passwd", "FILE:///tmp", "javascript:alert(1)", "data:text/html,hi", "x-apple.systempreferences:com.apple.preference.security",
                "notchnotch://extensions", "https://user:secret@example.com", "https:///no-host", "not a url", "", String(repeating: "a", count: 5000)] {
        #expect(throws: ProtocolError.self, "\(url)") { try OpenURLPolicy.validate(url) }
    }
}

@Test func activationAllowsOneOpenShortlyAfterAnInteraction() {
    var activation = UserActivation()
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let beforeAnyInteraction = activation.consume(now: start)
    activation.grant(now: start)
    let first = activation.consume(now: start.addingTimeInterval(1))
    let second = activation.consume(now: start.addingTimeInterval(1.1))
    activation.grant(now: start)
    let late = activation.consume(now: start.addingTimeInterval(UserActivation.window + 0.1))
    #expect(!beforeAnyInteraction)
    #expect(first)
    #expect(!second, "one open per interaction")
    #expect(!late, "the window expires")
}
