import Foundation
import Testing
@testable import NotchExtensions

@Test func storeLinksOpenOnlyWellFormedPages() {
    let valid: [(String, StoreLink)] = [
        ("notchnotch://extensions/sadeqi-ah/focus-timer", .entry(handle: "sadeqi-ah/focus-timer")),
        ("notchnotch://extensions/sadeqi-ah/focus-timer/", .entry(handle: "sadeqi-ah/focus-timer")),
        ("NOTCHNOTCH://Extensions/amir/clock", .entry(handle: "amir/clock")),
        ("notchnotch://extensions/amir/clock?ref=site", .entry(handle: "amir/clock")),
        ("notchnotch://store", .store),
        ("notchnotch://store/", .store),
    ]
    for (text, expected) in valid { #expect(StoreLink(URL(string: text)!) == expected, "\(text)") }

    let invalid = [
        "notchnotch://extensions/amir", "notchnotch://extensions/amir/clock/extra",
        "notchnotch://extensions/Amir/clock", "notchnotch://extensions/amir/..",
        "notchnotch://extensions/amir%2Fclock/x", "notchnotch://extensions/am%69r/clock",
        "notchnotch://user@extensions/amir/clock", "notchnotch://extensions:8080/amir/clock",
        "notchnotch://install/amir/clock", "notchnotch://store/amir", "https://extensions/amir/clock",
        "notchnotch:extensions/amir/clock",
    ]
    for text in invalid { #expect(URL(string: text).flatMap(StoreLink.init) == nil, "\(text)") }
    #expect(StoreLink.entry(handle: "amir/clock").url.absoluteString == "notchnotch://extensions/amir/clock")
}
