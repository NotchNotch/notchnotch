import SwiftUI
import NotchProtocol

/// The manifest's descriptive fields: who made the extension, what it is for
/// and where its code lives. Shows nothing for fields the manifest omits.
struct ExtensionAboutRows: View {
    let manifest: ExtensionManifest

    static func hasContent(_ manifest: ExtensionManifest) -> Bool {
        manifest.author != nil || manifest.categories != nil || manifest.license != nil ||
            manifest.homepage != nil || manifest.repository != nil
    }

    var body: some View {
        if let author = manifest.author { LabeledContent("Author", value: author).textSelection(.enabled) }
        if let categories = manifest.categories { LabeledContent("Categories", value: categories.joined(separator: ", ")) }
        if let license = manifest.license { LabeledContent("License", value: license) }
        link("Website", manifest.homepage)
        link("Source code", manifest.repository)
    }

    @ViewBuilder private func link(_ title: String, _ address: String?) -> some View {
        if let address, let url = URL(string: address), url.scheme == "https", let host = url.host() {
            LabeledContent(title) {
                Link(host, destination: url).help(address)
            }
        }
    }
}
