import AppKit
import SwiftUI
import NotchExtensions
import NotchRenderer
import NotchProtocol

struct ManagementExtensionPage: View {
    enum Tab: String, CaseIterable, Identifiable {
        case setup = "Setup", about = "About", access = "Access", developer = "Developer"
        var id: Self { self }
    }

    @Bindable var coordinator: ManagementCoordinator
    let record: InstalledExtension
    @State private var tab: Tab = .setup
    @State private var documents: [PackageDocument: String] = [:]
    @State private var secretKeys: [String] = []
    @State private var confirmingSecretDeletion = false

    private var model: AppModel { coordinator.model }
    private var status: ExtensionStatus { coordinator.status(of: record.id) }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
            if case .needsAttention(let message) = status { attention(message).padding(.horizontal, 24).padding(.bottom, 12) }
            Picker("Section", selection: $tab) {
                ForEach(tabs) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .padding(.bottom, 4)
            Form {
                switch tab {
                case .setup: setup
                case .about: about
                case .access: access
                case .developer: developer
                }
            }.formStyle(.grouped)
        }
        .task(id: record.directory) {
            let directory = record.directory
            documents = await Task.detached {
                var loaded: [PackageDocument: String] = [:]
                for document in PackageDocument.allCases { loaded[document] = document.load(from: directory) }
                return loaded
            }.value
            if tab == .about, documents.isEmpty { tab = .setup }
        }
        .task(id: "\(record.id)|\(tab)") {
            guard tab == .access else { return }
            let id = record.id
            secretKeys = await Task.detached { (try? ExtensionSecretStore().keys(extensionID: id)) ?? [] }.value
        }
    }

    /// About appears only for packages that include a README or CHANGELOG.
    private var tabs: [Tab] { Tab.allCases.filter { $0 != .about || !documents.isEmpty } }

    @ViewBuilder private var about: some View {
        if let readme = documents[.readme] {
            Section { MarkdownView(readme) }
        }
        if let changelog = documents[.changelog] {
            Section("Version History") { MarkdownView(changelog) }
        }
    }

    private var header: some View {
        @Bindable var model = coordinator.model
        return HStack(alignment: .center, spacing: 14) {
            ExtensionIdentityView(icon: record.icon, size: 48)
                .saturation(model.isEnabled(record.id) ? 1 : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.manifest.name).font(.title2).bold().lineLimit(1)
                Text(record.manifest.description ?? "Version \(record.manifest.version)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(status.title)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(record.manifest.version) · \(record.origin.rawValue)").foregroundStyle(.secondary)
                }.font(.caption)
            }
            Spacer(minLength: 12)
            Toggle("Enabled", isOn: $model[enabledFor: record.id])
                .toggleStyle(.switch).labelsHidden().controlSize(.large)
                .help(model.isEnabled(record.id) ? "Turn off \(record.manifest.name)" : "Turn on \(record.manifest.name)")
                .disabled(coordinator.busy)
        }
    }

    private var statusColor: Color {
        switch status {
        case .running: .green
        case .starting: .yellow
        case .off: .secondary
        case .needsAttention: .orange
        case .needsSetup: .yellow
        }
    }

    private func attention(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text(message).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).lineLimit(4)
            Button("Restart") { model.restartExtension(record.id) }.disabled(coordinator.busy)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var setup: some View {
        if model.isEnabled(record.id), !(record.manifest.preferences ?? []).isEmpty {
            ExtensionPreferencesForm(record: record, model: model, notify: coordinator.notify)
                .disabled(coordinator.busy)
        }
        if case .needsSetup(let missing) = status {
            Section {
                Label("Fill in \(ListFormatter.localizedString(byJoining: missing)) to start \(record.manifest.name).", systemImage: "gearshape")
                    .foregroundStyle(.secondary)
            }
        } else if !model.isEnabled(record.id) {
            Section {
                LabeledContent("\(record.manifest.name) is off") {
                    Button("Turn On") { model.setEnabled(true, for: record.id) }.disabled(coordinator.busy)
                }
            } footer: {
                Text("While it’s off, its activities are hidden and its app connections are closed.")
            }
        } else if let tree = model.extensionSettings[record.id] {
            ForEach(SettingsBlock.blocks(for: tree)) { block in
                Section {
                    ForEach(block.nodes) { node in
                        SettingsNodeView(node: node) { action, value in
                            model.sendSettings(extensionID: record.id, action: action, value: value)
                        }
                    }
                } header: {
                    if let title = block.title { Text(title) }
                } footer: {
                    if let footer = block.footer { Text(footer) }
                }
            }
            .id(model.extensionSessionIDs[record.id])
            .disabled(coordinator.busy)
        } else if status == .starting {
            Section {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Starting \(record.manifest.name)…").foregroundStyle(.secondary)
                }
            }
        } else if status == .running {
            Section {
                if model.canRevealActivity(record.id) {
                    LabeledContent("Activity") { Button("Show in Notch") { model.revealActivity(record.id) } }
                } else {
                    LabeledContent("Setup", value: "Nothing to set up")
                }
            } footer: {
                Text("Its activities appear in the notch when there’s something to show.")
            }
        }
    }

    @ViewBuilder private var access: some View {
        let connections = record.manifest.connections ?? [:]
        let remembered = model.alwaysAllowedConnections(record.id)
        Section {
            ManagementAccessView(manifest: record.manifest, alwaysAllowed: remembered)
        } footer: {
            if record.manifest.permissions.contains("process") {
                Text("Native tools run with your account. macOS asks separately when a tool needs privacy access.")
            }
        }
        if !secretKeys.isEmpty {
            Section {
                LabeledContent {
                    Button("Delete…", role: .destructive) { confirmingSecretDeletion = true }.disabled(coordinator.busy)
                } label: {
                    Text("Keychain secrets")
                    Text(secretKeys.joined(separator: ", "))
                }
            } footer: {
                Text("Tokens and passwords this extension saved in your Keychain. Only \(record.manifest.name) can read them.")
            }
            .confirmationDialog("Delete \(record.manifest.name)’s secrets?", isPresented: $confirmingSecretDeletion) {
                Button("Delete Secrets", role: .destructive) {
                    let id = record.id
                    Task {
                        try? await Task.detached { try ExtensionSecretStore().deleteAll(extensionID: id) }.value
                        secretKeys = []
                        coordinator.notify("\(record.manifest.name)’s secrets were deleted.")
                    }
                }
            } message: {
                Text("You may need to sign in again in its Setup.")
            }
        }
        if !connections.isEmpty {
            Section {
                LabeledContent {
                    Button("Disconnect") {
                        model.disconnectExtension(record.id)
                        coordinator.notify("\(record.manifest.name) disconnected.")
                    }.disabled(!model.isEnabled(record.id) || coordinator.busy)
                } label: {
                    Text("Open connections")
                    Text("Closes them now. The extension can ask to connect again.")
                }
                if !remembered.isEmpty {
                    LabeledContent {
                        Button("Forget") {
                            model.forgetAccess(record.id)
                            coordinator.notify("\(record.manifest.name) will ask again before connecting.")
                        }.disabled(coordinator.busy)
                    } label: {
                        Text("Always Allow")
                        Text("Remembered for \(remembered.sorted().joined(separator: ", ")).")
                    }
                }
            }
        }
    }

    @ViewBuilder private var developer: some View {
        Section {
            ExtensionLogView(entries: model.extensionLogs[record.id] ?? []) { model.clearLogs(record.id) }
        } header: {
            Text("Console")
        }
        Section("Package") {
            LabeledContent("Identifier", value: record.id).textSelection(.enabled)
            LabeledContent("Version", value: record.manifest.version)
            LabeledContent("Source", value: record.origin.rawValue)
            ExtensionAboutRows(manifest: record.manifest)
            LabeledContent {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([record.directory]) }
            } label: {
                Text("Location")
                Text(record.directory.path).textSelection(.enabled)
            }
        }
        Section {
            LabeledContent("Extension") {
                Button("Restart") { model.restartExtension(record.id) }
                    .disabled(!model.isEnabled(record.id) || coordinator.busy)
            }
            if model.extensionStore.isManaged(record) {
                LabeledContent("Installed package") {
                    Button("Remove…", role: .destructive) { coordinator.requestRemoval(record) }
                        .disabled(coordinator.busy)
                }
            }
        }
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
