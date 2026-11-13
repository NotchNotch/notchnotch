import SwiftUI
import NotchCore
import NotchProtocol
import NotchExtensions
import ServiceManagement

struct ManagementGeneralPage: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        @Bindable var model = coordinator.model
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin || model.launchAtLoginNeedsApproval },
                                                      set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                if model.launchAtLoginNeedsApproval {
                    LabeledContent("Allow NotchNotch in Login Items") {
                        Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = model.launchAtLoginError {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            } header: {
                Text("Startup")
            }
            .onAppear { model.refreshLaunchAtLogin() }
            Section {
                Toggle("Update Store extensions automatically", isOn: $model.updatesStoreExtensionsAutomatically).toggleStyle(.switch)
            } header: {
                Text("Store")
            } footer: {
                Text("Updates that ask for anything new, such as another website, wait in the Store for you to review.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Installed extensions") {
                    Button("Show in Finder", action: coordinator.showFolder)
                }
                LabeledContent("All extensions") {
                    Button("Restart") {
                        coordinator.model.reloadExtensions(force: true)
                        coordinator.notify("Extensions restarted.")
                    }.disabled(coordinator.busy)
                }
                LabeledContent("App connections") {
                    Button("Disconnect All") {
                        coordinator.model.disconnectExtensions()
                        coordinator.notify("App connections closed.")
                    }.disabled(coordinator.busy)
                }
            } header: {
                Text("Extensions")
            } footer: {
                Text("Disconnecting closes every local service and native helper. Each extension reconnects from its Setup tab.")
            }
            ProblemsSection(coordinator: coordinator)
        }.formStyle(.grouped)
    }
}

struct ManagementNotchPage: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        @Bindable var model = coordinator.model
        Form {
            Section {
                Picker("Show on", selection: $model.preferredDisplayID) {
                    Text("Automatic").tag(String?.none)
                    ForEach(model.displays) { display in
                        Text(display.hasNotch ? "\(display.name) (camera housing)" : display.name).tag(Optional(display.id))
                    }
                    if let id = model.preferredDisplayID, !model.displays.contains(where: { $0.id == id }) {
                        Text("Disconnected display").tag(Optional(id))
                    }
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Automatic uses the built-in display with a camera housing, or the main display. A disconnected choice falls back to Automatic until it returns.")
            }
            Section {
                Toggle("Expand on hover", isOn: $model.expandOnHover).toggleStyle(.switch)
            } header: {
                Text("Interaction")
            } footer: {
                Text("Keep the pointer over the notch to preview an activity. Clicking always opens it. Scroll sideways to switch between activities.")
            }
            Section {
                Toggle("Show hidden menu bar icons", isOn: $model.menuBarEnabled).toggleStyle(.switch)
                if model.menuBarEnabled, !model.menuBarTrusted {
                    HStack {
                        Label("Needs Accessibility", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings…") { model.requestMenuBarAccess() }
                    }
                } else if model.menuBarEnabled {
                    LabeledContent("Hidden now", value: model.hiddenMenuBarItems.isEmpty ? "None"
                                   : model.hiddenMenuBarItems.map(\.name).joined(separator: ", "))
                    Toggle(isOn: $model.menuBarExactIcons) {
                        Text("Show exact icons")
                        Text("Each icon's own image instead of its app's. Captured once when the notch opens, never recorded.")
                    }.toggleStyle(.switch)
                    if model.menuBarExactIcons, !model.menuBarCaptureGranted {
                        HStack {
                            Label("Needs Screen Recording", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open System Settings…") { MenuBarImages.request() }
                        }
                    }
                    LabeledContent {
                        Button("Rearrange Menu Bar…") { model.rearrangeMenuBar() }
                    } label: {
                        Text("Choose which icons hide")
                        Text("Or hold ⌘ with the pointer in the menu bar, then drag an icon across the divider.")
                    }
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text("Icons under the notch move off the menu bar and appear on the left of the open notch; clicking one opens its menu. Icons left of the divider hide; ⌘-drag one across it to choose. NotchNotch reads the menu bar with Accessibility and keeps what it finds on this Mac.")
            }
            HomeSettingsSection(model: model)
        }.formStyle(.grouped)
        .onAppear { model.updateMenuBar() }
    }
}

/// Home's order, pins, sizes and hidden tiles. The tiles' right-click menu
/// changes the same things, except bringing back a hidden one.
private struct HomeSettingsSection: View {
    let model: AppModel

    var body: some View {
        let activities = model.platform.homeActivities
        let preferences = model.platform.homePreferences
        Section {
            if activities.isEmpty {
                Text("Activities appear here while their extension is on.").foregroundStyle(.secondary)
            }
            ForEach(Array(activities.enumerated()), id: \.element.key) { index, item in
                HomeSettingsRow(item: item, record: model.installedExtensions.first { $0.id == item.key.extensionID },
                                preferences: preferences, edit: model.editHome)
                    .draggable(item.key.id) { Label(item.surface.title, systemImage: "line.3.horizontal").padding(6) }
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first else { return false }
                        move(id, to: index, in: activities)
                        return true
                    }
                    .contextMenu {
                        Button("Move Up") { move(item.key.id, to: index - 1, in: activities) }.disabled(index == 0)
                        Button("Move Down") { move(item.key.id, to: index + 1, in: activities) }.disabled(index == activities.count - 1)
                    }
                    .accessibilityActions {
                        if index > 0 { Button("Move Up") { move(item.key.id, to: index - 1, in: activities) } }
                        if index < activities.count - 1 { Button("Move Down") { move(item.key.id, to: index + 1, in: activities) } }
                    }
            }
        } header: {
            Text("Home")
        } footer: {
            Text("Drag to change the order. The first live activity in this order takes the wings. Pinned activities come first in Home; hidden ones still show in the wings while they’re live. Right-click a tile in Home for the same choices.")
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activities.map(\.key.id))
    }

    private func move(_ id: String, to index: Int, in activities: [HostedSurface]) {
        var keys = activities.map(\.key)
        guard let from = keys.firstIndex(where: { $0.id == id }), keys.indices.contains(index), from != index else { return }
        keys.insert(keys.remove(at: from), at: index)
        model.editHome { $0.reorder(keys) }
    }
}

private struct HomeSettingsRow: View {
    let item: HostedSurface
    let record: InstalledExtension?
    let preferences: HomePreferences
    let edit: ((inout HomePreferences) -> Void) -> Void

    var body: some View {
        let key = item.key
        let hidden = preferences.hidden.contains(key.id)
        let pinned = preferences.pinned.contains(key.id)
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
            if let record { ExtensionIdentityView(icon: record.icon, size: 20) }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.surface.title).lineLimit(1)
                if let name = record?.manifest.name, name != item.surface.title {
                    Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .opacity(hidden ? 0.5 : 1)
            Spacer(minLength: 8)
            Picker("Size", selection: Binding(get: { preferences.sizes[key.id] }, set: { size in edit { $0.setSize(size, key) } })) {
                Text("Automatic").tag(TileSize?.none)
                Text("Small").tag(TileSize?.some(.small))
                Text("Wide").tag(TileSize?.some(.wide))
            }
            .labelsHidden().fixedSize().disabled(hidden)
            Button { edit { $0.setPinned(!pinned, key) } } label: {
                Image(systemName: pinned ? "pin.fill" : "pin").frame(width: 18)
            }
            .buttonStyle(.borderless).disabled(hidden)
            .help(pinned ? "Unpin" : "Pin to the top of Home")
            .accessibilityLabel(pinned ? "Unpin \(item.surface.title)" : "Pin \(item.surface.title)")
            Button { edit { $0.setHidden(!hidden, key) } } label: {
                Image(systemName: hidden ? "eye.slash" : "eye").frame(width: 20)
            }
            .buttonStyle(.borderless)
            .help(hidden ? "Show in Home" : "Hide from Home")
            .accessibilityLabel(hidden ? "Show \(item.surface.title) in Home" : "Hide \(item.surface.title) from Home")
        }
        .contentShape(Rectangle())
    }
}

struct ManagementAboutPage: View {
    @Bindable var coordinator: ManagementCoordinator
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let short = info["CFBundleShortVersionString"] as? String else { return "Development build" }
        return "Version \(short) (\(info["CFBundleVersion"] as? String ?? "1"))"
    }
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NotchNotch").font(.title2).bold()
                        Text(version).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("Developer Preview").font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
            Section {
                if coordinator.updater.isAvailable {
                    @Bindable var updater = coordinator.updater
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks).toggleStyle(.switch)
                    Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloads)
                        .toggleStyle(.switch).disabled(!updater.automaticallyChecks)
                    LabeledContent {
                        Button("Check for Updates…", action: updater.checkForUpdates).disabled(!updater.canCheckForUpdates)
                    } label: {
                        Text("Software update")
                        if let date = updater.lastChecked {
                            Text("Last checked \(date.formatted(.relative(presentation: .named)))")
                        }
                    }
                } else {
                    LabeledContent("Software update", value: "Off in development builds")
                }
            } header: {
                Text("Updates")
            } footer: {
                if coordinator.updater.isAvailable {
                    Text("Updates come from GitHub Releases and are verified with NotchNotch’s signing key before they install.")
                }
            }
            Section("Resources") {
                link("Website", "https://notchnotch.github.io")
                link("Release notes", "https://notchnotch.github.io/changelog/")
                link("Build an extension", "https://notchnotch.github.io/docs/extensions/getting-started/")
                link("Privacy", "https://notchnotch.github.io/privacy/")
                link("Report an issue", "https://github.com/NotchNotch/notchnotch/issues")
            }
            Section {
                Text("Copyright © 2026 AmirHossein Sadeghi. Licensed under the GNU GPL v3.0; the extension SDK is MIT licensed.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func link(_ title: String, _ url: String) -> some View {
        LabeledContent(title) { Link("Open", destination: URL(string: url)!) }
    }
}

struct ManagementLibraryIssuesPage: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        Form {
            Section {
                ForEach(coordinator.model.libraryIssues.keys.sorted(), id: \.self) { path in
                    LabeledContent {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                    } label: {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                        Text(coordinator.model.libraryIssues[path] ?? "").textSelection(.enabled)
                    }
                }
            } footer: {
                Text("These folders in the extension library aren’t valid extensions. Fix or remove them, then reopen this window.")
            }
        }.formStyle(.grouped)
    }
}
