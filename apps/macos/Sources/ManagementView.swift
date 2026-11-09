import SwiftUI

struct ManagementView: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        VStack(spacing: 0) {
            if let error = coordinator.error {
                ManagementNotice(text: error, isError: true) { coordinator.error = nil }.padding()
                Divider()
            }
            destination
        }
        .frame(minWidth: 450, minHeight: 430)
        .overlay(alignment: .bottom) {
            if let message = coordinator.message {
                ManagementNotice(text: message, dismiss: coordinator.dismissMessage)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: coordinator.message)
        .sheet(item: $coordinator.sheet, onDismiss: { coordinator.sheetError = nil }) { item in
            ManagementReviewSheet(coordinator: coordinator, item: item)
        }
        .onChange(of: coordinator.model.installedExtensions.map(\.id)) { _, _ in coordinator.reconcileSelection() }
        .onChange(of: coordinator.model.libraryIssues.count) { _, _ in coordinator.reconcileSelection() }
        .onChange(of: pageTitle, initial: true) { _, title in coordinator.window?.subtitle = title }
    }
    private var pageTitle: String {
        switch coordinator.destination {
        case .general: "General"
        case .notch: "Notch"
        case .about: "About"
        case .libraryIssues: "Couldn’t Load"
        case .extensionDetails(let id): coordinator.model.installedExtensions.first(where: { $0.id == id })?.manifest.name ?? "Extension"
        }
    }
    @ViewBuilder private var destination: some View {
        switch coordinator.destination {
        case .general: ManagementGeneralPage(coordinator: coordinator)
        case .notch: ManagementNotchPage(coordinator: coordinator)
        case .about: ManagementAboutPage(coordinator: coordinator)
        case .libraryIssues: ManagementLibraryIssuesPage(coordinator: coordinator)
        case .extensionDetails(let id):
            if let record = coordinator.model.installedExtensions.first(where: { $0.id == id }) {
                ManagementExtensionPage(coordinator: coordinator, record: record).id(id)
            } else {
                ContentUnavailableView("Extension unavailable", systemImage: "puzzlepiece.extension",
                    description: Text("It may have been removed. Choose another extension."))
            }
        }
    }
}
