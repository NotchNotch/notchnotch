import Foundation
import Testing
import NotchProtocol

private func manifest(_ extra: String) throws -> ExtensionManifest {
    try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
    {"id":"dev.test.meta","name":"Meta","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[]\(extra)}
    """.utf8))
}

@Test func storeMetadataIsOptionalAndDecodedWhenPresent() throws {
    try manifest("").validate()
    let full = try manifest("""
    ,"author":"jane-doe","categories":["Media","Productivity"],"license":"MIT OR Apache-2.0",
    "homepage":"https://example.com","repository":"https://github.com/example/repo"
    """)
    try full.validate()
    #expect(full.author == "jane-doe")
    #expect(full.categories == ["Media", "Productivity"])
}

@Test func invalidStoreMetadataIsRejected() throws {
    let invalid = [
        #","author":"Jane Doe""#, #","author":"-jane""#, #","author":"jane-""#,
        #","categories":[]"#, #","categories":["Games"]"#, #","categories":["Fun","Fun"]"#,
        #","categories":["Fun","Media","News","System"]"#,
        #","homepage":"http://example.com""#, #","homepage":"javascript:alert(1)""#,
        #","repository":"https://user:secret@example.com""#, #","repository":"https://""#,
        #","license":"MIT; rm -rf""#, #","license":"""#,
    ]
    for extra in invalid {
        #expect(throws: ProtocolError.self, "\(extra)") { try manifest(extra).validate() }
    }
}
