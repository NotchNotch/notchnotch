import SwiftUI
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
        }.formStyle(.grouped)
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
                link("Release notes", "https://github.com/sadeqi-ah/notchnotch/blob/main/CHANGELOG.md")
                link("Build an extension", "https://github.com/sadeqi-ah/notchnotch/blob/main/docs/extensions/getting-started.md")
                link("Privacy", "https://github.com/sadeqi-ah/notchnotch/blob/main/PRIVACY.md")
                link("Report an issue", "https://github.com/sadeqi-ah/notchnotch/issues")
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
