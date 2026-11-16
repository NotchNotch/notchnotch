import SwiftUI

struct ManagementSidebar: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        VStack(spacing: 0) {
            ManagementSearchField(text: $coordinator.query)
                .frame(height: 24).padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
            List(selection: $coordinator.destination) {
                if coordinator.query.isEmpty {
                    Section {
                        AppCard().tag(ManagementDestination.about)
                    }
                    Section {
                        row("General", symbol: "gearshape.fill", color: .gray, .general)
                        row("Notch", symbol: "rectangle.topthird.inset.filled", color: .indigo, .notch)
                        Label { Text("Store") } icon: { SettingsIconTile(symbol: "bag.fill", color: .pink) }
                            .badge(coordinator.model.storeUpdates.count)
                            .tag(ManagementDestination.store)
                    }
                }
                Section("Extensions") {
                    ForEach(coordinator.visibleExtensions) { record in
                        HStack {
                            Label {
                                Text(record.manifest.name).lineLimit(1)
                            } icon: {
                                ExtensionIdentityView(icon: record.icon, size: 22, tile: true)
                                    .saturation(coordinator.model.isEnabled(record.id) ? 1 : 0)
                            }
                            Spacer(minLength: 0)
                            StatusIndicator(status: coordinator.status(of: record.id))
                        }
                        .tag(ManagementDestination.extensionDetails(record.id))
                        .contextMenu {
                            if coordinator.model.canUninstall(record) {
                                Button("Uninstall…", role: .destructive) { coordinator.requestRemoval(record) }
                            }
                        }
                    }
                    if coordinator.visibleExtensions.isEmpty {
                        Text(coordinator.query.isEmpty ? "No extensions" : "No matches").foregroundStyle(.secondary)
                    }
                    if coordinator.query.isEmpty, !coordinator.model.libraryIssues.isEmpty {
                        Label {
                            Text("Couldn’t Load (\(coordinator.model.libraryIssues.count))")
                        } icon: {
                            SettingsIconTile(symbol: "exclamationmark.triangle.fill", color: .orange)
                        }.tag(ManagementDestination.libraryIssues)
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack {
                Button(action: coordinator.choosePackage) {
                    Label("Install Extension from Folder…", systemImage: "plus")
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help("Install an extension from a folder")
                .disabled(coordinator.busy).keyboardShortcut("i", modifiers: [.command, .shift])
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func row(_ title: String, symbol: String, color: Color, _ destination: ManagementDestination) -> some View {
        Label { Text(title) } icon: { SettingsIconTile(symbol: symbol, color: color) }.tag(destination)
    }
}

/// NotchNotch itself at the top of the sidebar, as System Settings shows your
/// account: opens About, with the version and updates.
private struct AppCard: View {
    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "Version \($0)" } ?? "Development build"
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("NotchNotch").font(.headline)
                Text(version).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("About NotchNotch and updates")
    }
}

struct StatusIndicator: View {
    let status: ExtensionStatus
    var body: some View {
        switch status {
        case .running: EmptyView()
        case .starting: ProgressView().controlSize(.mini).help(status.title)
        case .off: Text("Off").font(.caption).foregroundStyle(.secondary)
        case .needsAttention: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).help(status.title)
        case .needsSetup: Image(systemName: "gearshape.fill").foregroundStyle(.yellow).help(status.title)
        }
    }
}
