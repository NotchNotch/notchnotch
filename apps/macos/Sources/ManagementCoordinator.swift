import AppKit
import Observation
import NotchExtensions

@MainActor @Observable
final class ManagementCoordinator {
    let model: AppModel
    let updater: AppUpdater
    var destination: ManagementDestination = .general {
        didSet { if destination != oldValue { error = nil } }
    }
    var query = "" {
        didSet {
            if case .extensionDetails(let id) = destination, !visibleExtensions.contains(where: { $0.id == id }) {
                destination = .general
            }
        }
    }
    var sheet: ManagementSheet?
    var sheetError: String?
    /// Errors stay until dismissed; messages fade out on their own.
    var error: String?
    private(set) var message: String?
    @ObservationIgnored private var messageGeneration = 0
    private(set) var choosingPackage = false
    private(set) var operating = false
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var picker: NSOpenPanel?
    @ObservationIgnored private var pickerGeneration = 0

    init(model: AppModel, updater: AppUpdater) { self.model = model; self.updater = updater }
    var busy: Bool { choosingPackage || operating }
    var visibleExtensions: [InstalledExtension] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.installedExtensions.filter { term.isEmpty || $0.manifest.name.localizedCaseInsensitiveContains(term) || $0.id.localizedCaseInsensitiveContains(term) }
    }
    var enabledCount: Int { model.installedExtensions.filter { model.isEnabled($0.id) }.count }

    func status(of id: String) -> ExtensionStatus {
        if !model.isEnabled(id) { return .off }
        if let error = model.errors[id] { return .needsAttention(error) }
        return model.hasRendered(id) ? .running : .starting
    }

    func notify(_ text: String) {
        messageGeneration += 1
        let generation = messageGeneration
        message = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if generation == messageGeneration { message = nil }
        }
    }
    func dismissMessage() { messageGeneration += 1; message = nil }

    func selectExtension(_ id: String) {
        guard model.installedExtensions.contains(where: { $0.id == id }) else { return }
        query = ""
        destination = .extensionDetails(id)
    }
    func reconcileSelection() {
        if case .extensionDetails(let id) = destination, !model.installedExtensions.contains(where: { $0.id == id }) { destination = .general }
        if destination == .libraryIssues, model.libraryIssues.isEmpty { destination = .general }
    }
    func choosePackage() {
        guard !busy, sheet == nil, let window else { return }
        choosingPackage = true
        error = nil
        dismissMessage()
        pickerGeneration += 1
        let generation = pickerGeneration
        let panel = NSOpenPanel()
        picker = panel
        panel.title = "Install Extension"
        panel.message = "Choose a built extension folder containing notchnotch.json and bundle.js."
        panel.prompt = "Review Extension"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        Task { @MainActor in
            defer { if generation == pickerGeneration { choosingPackage = false; picker = nil } }
            guard await panel.beginSheetModal(for: window) == .OK, let folder = panel.url else { return }
            do {
                let package = try await model.reviewInstall(folder)
                guard generation == pickerGeneration else { return }
                sheetError = nil
                sheet = .install(package)
            } catch { if generation == pickerGeneration { self.error = error.localizedDescription } }
        }
    }
    func confirmInstall(_ package: ExtensionPackage) {
        guard !operating else { return }
        let updating = model.installedExtensions.contains { $0.id == package.id }
        operating = true
        sheetError = nil
        Task { @MainActor in
            defer { operating = false }
            do {
                try await model.installExtension(package)
                sheet = nil
                selectExtension(package.id)
                notify("\(package.manifest.name) \(updating ? "updated" : "installed").")
            } catch { sheetError = error.localizedDescription }
        }
    }
    func requestRemoval(_ record: InstalledExtension) {
        guard !busy, model.extensionStore.isManaged(record) else { return }
        sheetError = nil
        sheet = .remove(record)
    }
    func confirmRemoval(_ record: InstalledExtension) {
        guard !operating else { return }
        operating = true
        sheetError = nil
        Task { @MainActor in
            defer { operating = false }
            do {
                try await model.removeExtension(record)
                sheet = nil
                destination = .general
                notify("\(record.manifest.name) moved to Trash.")
            } catch { sheetError = error.localizedDescription }
        }
    }
    func dismissSheet() {
        guard !operating else { return }
        sheet = nil
        sheetError = nil
    }
    func windowClosed() {
        pickerGeneration += 1
        picker?.cancel(nil)
        picker = nil
        choosingPackage = false
        if !operating { dismissSheet() }
    }
    func showFolder() {
        do {
            try FileManager.default.createDirectory(at: model.extensionStore.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(model.extensionStore.directory)
        } catch { self.error = error.localizedDescription }
    }
}
