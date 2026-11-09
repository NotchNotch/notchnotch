import SwiftUI
import NotchProtocol

struct ManagementAccessView: View {
    let manifest: ExtensionManifest
    var alwaysAllowed: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if manifest.permissions.isEmpty && (manifest.imageHosts ?? []).isEmpty && (manifest.network ?? []).isEmpty {
                Label("This extension doesn’t request access to other apps.", systemImage: "checkmark.shield").foregroundStyle(.secondary)
            }
            if manifest.permissions.contains("process") {
                Label("Run native tools", systemImage: "terminal").font(.headline)
                Text("Declared tools run with your account. You’re asked before the first connection; choose Always Allow to skip the question next time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if manifest.permissions.contains("local-network") {
                Label("Connect to local apps", systemImage: "network").font(.headline)
                Text("Only the local destinations listed below can be contacted.").font(.callout).foregroundStyle(.secondary)
            }
            if let hosts = manifest.network, !hosts.isEmpty {
                Label("Connect to the internet", systemImage: "globe").font(.headline)
                Text("The extension can send and receive data over HTTPS, without asking again, but only with these hosts.")
                    .font(.callout).foregroundStyle(.secondary)
                Text(hosts.joined(separator: ", ")).font(.callout.monospaced()).textSelection(.enabled)
            }
            if let hosts = manifest.imageHosts, !hosts.isEmpty {
                Label("Load artwork from the web", systemImage: "photo").font(.headline)
                Text("NotchNotch downloads images for this extension only from these hosts.").font(.callout).foregroundStyle(.secondary)
                Text(hosts.joined(separator: ", ")).font(.callout.monospaced()).textSelection(.enabled)
            }
            ForEach((manifest.connections ?? [:]).keys.sorted(), id: \.self) { id in
                if let connection = manifest.connections?[id] {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(id).font(.headline)
                            if alwaysAllowed.contains(id) {
                                Text("Always allowed").font(.caption).foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        Text(connection.endpoint ?? connection.executable ?? "").font(.callout.monospaced()).textSelection(.enabled)
                        if let arguments = connection.arguments, !arguments.isEmpty {
                            Text(arguments.joined(separator: " ")).font(.callout.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
