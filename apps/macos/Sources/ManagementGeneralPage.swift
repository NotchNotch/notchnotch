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
            }
            .onAppear { model.refreshLaunchAtLogin() }
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
            } footer: {
                Text("Automatic uses the built-in display with a camera housing, or the main display. A disconnected choice falls back to Automatic until it returns.")
            }
            Section {
                Toggle("Expand on hover", isOn: $model.expandOnHover).toggleStyle(.switch)
            } footer: {
                Text("Keep the pointer over the notch to preview an activity. Clicking always opens it.")
            }
            Section {
                LabeledContent("Local services and native helpers") {
                    Button("Disconnect All") {
                        coordinator.model.disconnectExtensions()
                        coordinator.message = "App connections closed. Reconnect from an extension’s setup page."
                    }.disabled(coordinator.busy)
                }
            } header: {
                Text("App Connections")
            } footer: {
                Text("Reconnect from each extension’s setup page.")
            }
            Section("Extension Library") {
                LabeledContent("Installed on this Mac") {
                    Button("Show in Finder", action: coordinator.showFolder)
                }
            }
            Section("About") {
                LabeledContent("NotchNotch", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                LabeledContent("Release", value: "Developer Preview")
            }
        }.formStyle(.grouped)
    }
}
