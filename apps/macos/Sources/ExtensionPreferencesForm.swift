import SwiftUI
import NotchExtensions
import NotchProtocol

/// The preferences an extension declares, drawn as native form rows at the top
/// of Setup. Edits are saved together with Save, which restarts the extension.
struct ExtensionPreferencesForm: View {
    let record: InstalledExtension
    let model: AppModel
    let notify: (String) -> Void

    @State private var edits: [String: JSONValue] = [:]
    @State private var saved: [String: JSONValue] = [:]
    @State private var saving = false
    @State private var error: String?

    private var preferences: [ExtensionPreference] { record.manifest.preferences ?? [] }
    private var hasChanges: Bool { edits.contains { saved[$0.key] != $0.value } }

    var body: some View {
        Section {
            ForEach(preferences, id: \.name) { field(for: $0) }
            HStack {
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Save") { save() }.disabled(!hasChanges || saving)
            }
        } header: {
            Text("Preferences")
        } footer: {
            Text("Saving restarts \(record.manifest.name). Passwords are kept in your Keychain.")
        }
        .task(id: record.id) { load() }
    }

    @ViewBuilder private func field(for preference: ExtensionPreference) -> some View {
        let label = VStack(alignment: .leading) {
            Text(preference.title + (preference.isRequired ? " (required)" : ""))
            if let description = preference.description { Text(description) }
        }
        switch preference.type {
        case .text:
            TextField(text: text(preference), prompt: preference.placeholder.map(Text.init)) { label }
        case .password:
            // A saved password is never shown; typing replaces it.
            SecureField(text: text(preference), prompt: Text(saved[preference.name] == nil ? preference.placeholder ?? "" : "Saved")) { label }
        case .toggle:
            Toggle(isOn: Binding(
                get: { if case let .bool(on)? = value(preference) { return on }; return false },
                set: { edits[preference.name] = .bool($0) })) { label }
        case .dropdown:
            Picker(selection: Binding(
                get: { if case let .string(selected)? = value(preference) { return selected }; return "" },
                set: { edits[preference.name] = .string($0) })) {
                if value(preference) == nil { Text("Choose…").tag("") }
                ForEach(preference.options ?? [], id: \.value) { Text($0.title).tag($0.value) }
            } label: { label }
        }
    }

    private func value(_ preference: ExtensionPreference) -> JSONValue? { edits[preference.name] ?? saved[preference.name] }

    private func text(_ preference: ExtensionPreference) -> Binding<String> {
        Binding(
            get: {
                if case let .string(text)? = edits[preference.name] { return text }
                if preference.type != .password, case let .string(text)? = saved[preference.name] { return text }
                return ""
            },
            set: { edits[preference.name] = .string($0) })
    }

    private func load() {
        saved = model.preferenceStore.summary(for: record.manifest)
        edits = [:]
        error = nil
    }

    private func save() {
        // An untouched or emptied password field keeps the saved password.
        let changes = edits.filter { name, value in
            guard saved[name] != value else { return false }
            if preferences.first(where: { $0.name == name })?.type == .password, case .string("") = value { return false }
            return true
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await model.savePreferences(changes, for: record)
                load()
                notify("\(record.manifest.name) preferences saved.")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
