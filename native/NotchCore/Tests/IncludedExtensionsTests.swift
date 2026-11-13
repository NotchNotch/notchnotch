import Testing
import NotchCore

@Test func aNewIncludedExtensionIsInstalledOnceForEveryone() {
    var installed: Set<String> = ["music"], offered: Set<String> = []
    IncludedExtensions.introduce(["shelf"], available: ["music", "shelf"], installed: &installed, offered: &offered)
    #expect(installed == ["music", "shelf"])
    #expect(offered == ["shelf"])

    // Uninstalled afterwards: it stays uninstalled.
    installed.remove("shelf")
    IncludedExtensions.introduce(["shelf"], available: ["music", "shelf"], installed: &installed, offered: &offered)
    #expect(installed == ["music"])
}

@Test func anExtensionMissingFromTheAppIsNotOfferedYet() {
    var installed: Set<String> = [], offered: Set<String> = []
    IncludedExtensions.introduce(["shelf"], available: ["music"], installed: &installed, offered: &offered)
    #expect(installed.isEmpty)
    #expect(offered.isEmpty)
}
