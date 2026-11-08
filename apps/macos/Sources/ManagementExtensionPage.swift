import AppKit
import SwiftUI
import NotchExtensions
import NotchRenderer
import NotchProtocol

struct ManagementExtensionPage: View {
    @Bindable var coordinator: ManagementCoordinator
    let record: InstalledExtension
    @State private var showAccess = false
    @State private var showPackage = false
    @State private var showConsole = false

    var body: some View {
        @Bindable var model = coordinator.model
        Form {
            Section {
                Toggle(isOn: $model[enabledFor: record.id]) {
                    Label {
                        Text("Enable \(record.manifest.name)")
                    } icon: {
                        ExtensionIdentityView(manifest: record.manifest)
                    }
                }.toggleStyle(.switch).disabled(coordinator.busy)
            } footer: {
                Text(coordinator.model.isEnabled(record.id)
                    ? record.manifest.description ?? "This extension can show activities in your notch."
                    : "This extension’s activities and app connections are stopped.")
            }
            if let error = coordinator.model.errors[record.id] {
                Section {
                    Label("This extension needs attention", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).textSelection(.enabled)
                    HStack {
                        Spacer()
                        Button("Try Restarting") { coordinator.model.restartExtension(record.id) }
                            .disabled(!coordinator.model.isEnabled(record.id) || coordinator.busy)
                    }
                }
            }
            if coordinator.model.isEnabled(record.id) {
                if let tree = coordinator.model.extensionSettings[record.id] {
                    ForEach(SettingsBlock.blocks(for: tree)) { block in
                        Section {
                            ForEach(block.nodes) { node in
                                SettingsNodeView(node: node) { action, value in
                                    coordinator.model.sendSettings(extensionID: record.id, action: action, value: value)
                                }
                            }
                        } header: {
                            Text(block.title ?? "Setup")
                        } footer: {
                            if let footer = block.footer { Text(footer) }
                        }
                    }
                    .id(coordinator.model.extensionSessionIDs[record.id])
                    .disabled(coordinator.busy)
                } else if !coordinator.model.hasRendered(record.id), coordinator.model.errors[record.id] == nil {
                    Section {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Starting extension…").foregroundStyle(.secondary)
                        }
                    }
                } else if coordinator.model.errors[record.id] == nil {
                    Section {
                        if coordinator.model.canRevealActivity(record.id) {
                            LabeledContent("Activity") {
                                Button("Open in Notch") { coordinator.model.revealActivity(record.id) }
                            }
                        } else {
                            LabeledContent("Status", value: "Ready")
                        }
                    } footer: {
                        Text("No additional setup is required. Activities appear in the notch when you need them.")
                    }
                }
            }
            Section {
                DisclosureGroup("App Access", isExpanded: $showAccess) {
                    ManagementAccessView(manifest: record.manifest,
                                         alwaysAllowed: coordinator.model.alwaysAllowedConnections(record.id))
                }
                DisclosureGroup(isExpanded: $showConsole) {
                    ExtensionLogView(entries: coordinator.model.extensionLogs[record.id] ?? []) {
                        coordinator.model.clearLogs(record.id)
                    }
                } label: {
                    LabeledContent("Console") {
                        if let count = coordinator.model.extensionLogs[record.id]?.count, count > 0 {
                            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                DisclosureGroup("Package Details", isExpanded: $showPackage) {
                    LabeledContent("Version", value: record.manifest.version)
                    LabeledContent("Source", value: record.origin.rawValue)
                    LabeledContent("Identifier", value: record.id).textSelection(.enabled)
                    Text(record.directory.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([record.directory]) }
                    }
                }
            }
            Section("Maintenance") {
                LabeledContent("Extension") {
                    Button("Restart") { coordinator.model.restartExtension(record.id) }
                        .disabled(!coordinator.model.isEnabled(record.id) || coordinator.busy)
                }
                if !(record.manifest.connections ?? [:]).isEmpty {
                    LabeledContent("App connections") {
                        Button("Disconnect") { coordinator.model.disconnectExtension(record.id) }
                            .disabled(!coordinator.model.isEnabled(record.id) || coordinator.busy)
                    }
                }
                if !coordinator.model.alwaysAllowedConnections(record.id).isEmpty {
                    LabeledContent("Saved access") {
                        Button("Forget App Access") { coordinator.model.forgetAccess(record.id) }
                            .disabled(coordinator.busy)
                    }
                }
                if coordinator.model.extensionStore.isManaged(record) {
                    LabeledContent("Installed package") {
                        Button("Remove Extension…", role: .destructive) { coordinator.requestRemoval(record) }
                            .disabled(coordinator.busy)
                    }
                }
            }
        }.formStyle(.grouped)
    }
}

/// Root-level `section` nodes become native form sections; consecutive loose
/// nodes are grouped into an untitled "Setup" section between them.
private struct SettingsBlock: Identifiable {
    let id: String
    let title: String?
    let footer: String?
    let nodes: [UINode]

    static func blocks(for root: UINode) -> [SettingsBlock] {
        var blocks: [SettingsBlock] = []
        var loose: [UINode] = []
        func flush() {
            guard let first = loose.first else { return }
            blocks.append(.init(id: "loose-\(first.id)", title: nil, footer: nil, nodes: loose))
            loose = []
        }
        for node in root.children {
            if node.type == .section {
                flush()
                blocks.append(.init(id: node.id, title: node.props.text, footer: node.props.detail, nodes: node.children))
            } else { loose.append(node) }
        }
        flush()
        return blocks
    }
}
