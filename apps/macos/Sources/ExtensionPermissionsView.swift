import SwiftUI
import NotchExtensions
import NotchProtocol

/// The install review's account of what an extension can do, riskiest first.
/// For an update, anything the installed version couldn't do is marked New.
struct ExtensionPermissionsView: View {
    let manifest: ExtensionManifest
    var previous: ExtensionManifest?

    private var items: [PermissionSummary.Item] { PermissionSummary.items(for: manifest, comparedTo: previous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(items.isEmpty
                     ? "Runs in a sandbox and asks for nothing else. It can’t read your files, use the internet or start programs."
                     : "Runs in a sandbox: it can’t read your files, use the internet or start programs on its own. It can also:")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            }
            ForEach(items) { item in
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.title).font(.headline)
                            if item.isNew, previous != nil { NewBadge() }
                        }
                        Text(item.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(item.details, id: \.text) { detail in
                            HStack(spacing: 6) {
                                Text(detail.text).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2)
                                if detail.isNew, item.details.count > 1 { NewBadge() }
                            }
                        }
                    }
                } icon: {
                    Image(systemName: symbol(item.kind)).foregroundStyle(color(item.kind)).frame(width: 20)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func symbol(_ kind: PermissionSummary.Kind) -> String {
        switch kind {
        case .runPrograms: "terminal.fill"
        case .personalData: "person.crop.circle"
        case .internet: "globe"
        case .localApps: "network"
        case .pictures: "photo"
        case .settings: "slider.horizontal.3"
        }
    }

    private func color(_ kind: PermissionSummary.Kind) -> Color {
        switch kind {
        case .runPrograms: .orange
        case .personalData: .purple
        case .internet: .blue
        case .localApps: .teal
        case .pictures: .purple
        case .settings: .secondary
        }
    }
}

private struct NewBadge: View {
    var body: some View {
        Text("New").font(.caption2.bold()).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.orange, in: Capsule())
            .accessibilityLabel("New in this update")
    }
}
