import SwiftUI
import NotchExtensions

struct ManagementReviewSheet: View {
    @Bindable var coordinator: ManagementCoordinator
    let item: ManagementSheet
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = coordinator.sheetError { ManagementNotice(text: error, isError: true) }
                    details
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 160, maxHeight: 320)
            Divider()
            HStack(spacing: 12) {
                if coordinator.operating {
                    ProgressView().controlSize(.small)
                    Text(progressTitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: coordinator.dismissSheet).disabled(coordinator.operating)
                    .keyboardShortcut(.cancelAction)
                confirmButton.disabled(coordinator.operating).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 510).interactiveDismissDisabled(coordinator.operating)
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            switch item {
            case .install(let package, _):
                ExtensionIdentityView(icon: package.icon, size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(isUpdate ? "Update \(package.manifest.name)?" : "Install \(package.manifest.name)?").font(.title2).bold().lineLimit(2)
                    Text("Version \(package.manifest.version) · \(ByteCountFormatter.string(fromByteCount: Int64(package.byteCount), countStyle: .file))")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            case .remove(let record):
                Image(systemName: "trash").font(.title).foregroundStyle(.secondary).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Uninstall \(record.manifest.name)?").font(.title2).bold().lineLimit(2)
                    Text(record.origin == .bundled ? "It goes back to the Store." : "Its installed folder will move to Trash.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
    @ViewBuilder private var details: some View {
        switch item {
        case .install(let package, let entry):
            let old = coordinator.model.installedExtensions.first(where: { $0.id == package.id })
            if let old {
                Text("This replaces version \(old.manifest.version). Its settings and data are kept.").font(.callout).foregroundStyle(.secondary)
            }
            if let description = package.manifest.description { Text(description) }
            if ExtensionAboutRows.hasContent(package.manifest) {
                VStack(alignment: .leading, spacing: 6) { ExtensionAboutRows(manifest: package.manifest) }.font(.callout)
            }
            Text(package.id).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Divider()
            ExtensionPermissionsView(manifest: package.manifest, previous: old?.manifest)
            if let entry {
                Label("Reviewed for the NotchNotch Store and checked against its catalog. Published by \(entry.author).", systemImage: "checkmark.seal")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Install only extensions you trust.").font(.callout).foregroundStyle(.secondary)
            }
        case .remove(let record):
            Text("\(record.manifest.name)’s activities will close, its app connections will stop, and its settings and saved data will be deleted. \(record.origin == .bundled ? "You can get it again from the Store." : "You can recover its folder from Trash or install it again later.")")
                .foregroundStyle(.secondary)
        }
    }
    private var isUpdate: Bool {
        if case .install(let package, _) = item { return coordinator.model.installedExtensions.contains { $0.id == package.id } }
        return false
    }
    private var progressTitle: String {
        switch item { case .install: isUpdate ? "Updating…" : "Installing…"; case .remove(let record): record.origin == .bundled ? "Uninstalling…" : "Moving to Trash…" }
    }
    @ViewBuilder private var confirmButton: some View {
        switch item {
        case .install(let package, let entry):
            Button(isUpdate ? "Update Extension" : "Install Extension") { coordinator.confirmInstall(package, from: entry) }.buttonStyle(.borderedProminent)
        case .remove(let record):
            Button("Uninstall", role: .destructive) { coordinator.confirmRemoval(record) }.buttonStyle(.borderedProminent)
        }
    }
}
