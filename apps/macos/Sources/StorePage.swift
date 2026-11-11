import SwiftUI
import NotchExtensions
import NotchProtocol

/// The Store: every reviewed extension, with updates for installed ones first.
struct StorePage: View {
    @Bindable var coordinator: ManagementCoordinator
    @State private var search = ""
    @State private var category: String?
    private var store: StoreModel { coordinator.model.store }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search the Store", text: $search).textFieldStyle(.roundedBorder)
                Picker("Category", selection: $category) {
                    Text("All Categories").tag(String?.none)
                    Divider()
                    ForEach(ExtensionCategory.all, id: \.self) { Text($0).tag(Optional($0)) }
                }.labelsHidden().fixedSize()
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("Check the Store again").accessibilityLabel("Check the Store again").disabled(store.phase == .loading)
            }.padding(12)
            Divider()
            content
        }
        .task { await store.open() }
    }

    @ViewBuilder private var content: some View {
        let included = filteredIncluded
        if store.client == nil, included.isEmpty {
            ContentUnavailableView("Store unavailable", systemImage: "bag",
                description: Text("This build of NotchNotch has no Store settings."))
        } else if let catalog = store.catalog {
            let entries = filtered(catalog.extensions)
            if catalog.extensions.isEmpty, coordinator.model.includedExtensions.isEmpty {
                ContentUnavailableView("No extensions yet", systemImage: "bag",
                    description: Text("Reviewed extensions appear here as they’re published."))
            } else if entries.isEmpty, included.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    if case .failed(let message) = store.phase {
                        ManagementNotice(text: "Showing the Store as last checked. \(message)", isError: true)
                    }
                    let updates = entries.filter { if case .update = coordinator.model.storeState(of: $0) { true } else { false } }
                    if !updates.isEmpty {
                        Section("Updates") { ForEach(updates) { StoreRow(coordinator: coordinator, entry: $0) } }
                    }
                    includedSection(included)
                    if !entries.isEmpty {
                        Section(updates.isEmpty && included.isEmpty ? "" : "All Extensions") {
                            ForEach(entries) { StoreRow(coordinator: coordinator, entry: $0) }
                        }
                    }
                }.listStyle(.inset)
            }
        } else if !included.isEmpty {
            // The catalog isn't here yet, but what ships inside the app is.
            List {
                includedSection(included)
                Section {
                    if case .failed(let message) = store.phase {
                        ManagementNotice(text: "Couldn’t open the Store. \(message)", isError: true)
                        Button("Try Again") { Task { await store.refresh() } }
                    } else if store.client != nil {
                        HStack { ProgressView().controlSize(.small); Text("Opening the Store…").foregroundStyle(.secondary) }
                    }
                }
            }.listStyle(.inset)
        } else if case .failed(let message) = store.phase {
            ContentUnavailableView {
                Label("Couldn’t open the Store", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await store.refresh() } }
            }
        } else {
            ProgressView("Opening the Store…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func includedSection(_ records: [InstalledExtension]) -> some View {
        if !records.isEmpty {
            Section("Included with NotchNotch") {
                ForEach(records) { IncludedRow(coordinator: coordinator, record: $0) }
            }
        }
    }

    private var filteredIncluded: [InstalledExtension] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return coordinator.model.includedExtensions.filter { record in
            (category.map { (record.manifest.categories ?? []).contains($0) } ?? true) &&
            (term.isEmpty || [record.manifest.name, record.manifest.description ?? ""].contains { $0.localizedCaseInsensitiveContains(term) })
        }
    }

    private func filtered(_ entries: [ExtensionCatalog.Entry]) -> [ExtensionCatalog.Entry] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            (category.map { (entry.manifest.categories ?? []).contains($0) } ?? true) &&
            (term.isEmpty || [entry.manifest.name, entry.manifest.description ?? "", entry.author, entry.handle]
                .contains { $0.localizedCaseInsensitiveContains(term) })
        }.sorted { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
    }
}

private struct StoreRow: View {
    let coordinator: ManagementCoordinator
    let entry: ExtensionCatalog.Entry
    var body: some View {
        HStack(spacing: 12) {
            Button { coordinator.openStoreEntry(entry.handle) } label: {
                HStack(spacing: 12) {
                    StoreIcon(entry: entry, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.manifest.name).font(.headline).lineLimit(1)
                        if let description = entry.manifest.description {
                            Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text(entry.author).font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            StoreActionButton(coordinator: coordinator, entry: entry)
        }.padding(.vertical, 4)
    }
}

/// An extension that ships inside the app: Get installs it, Open shows its page.
private struct IncludedRow: View {
    let coordinator: ManagementCoordinator
    let record: InstalledExtension
    var body: some View {
        let installed = coordinator.model.isInstalled(record.id)
        HStack(spacing: 12) {
            ExtensionIdentityView(icon: record.icon, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.manifest.name).font(.headline).lineLimit(1)
                if let description = record.manifest.description {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(record.manifest.author ?? "NotchNotch").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if installed {
                Button("Open") { coordinator.selectExtension(record.id) }.buttonStyle(.bordered)
            } else {
                Button("Get") { coordinator.installIncluded(record) }.buttonStyle(.bordered).disabled(coordinator.busy)
            }
        }.padding(.vertical, 4)
    }
}

/// Get, Update or Open, depending on what's installed.
struct StoreActionButton: View {
    let coordinator: ManagementCoordinator
    let entry: ExtensionCatalog.Entry
    var prominent = false
    var body: some View {
        if coordinator.downloadingID == entry.id {
            ProgressView().controlSize(.small).frame(minWidth: 60)
        } else {
            switch coordinator.model.storeState(of: entry) {
            case .install:
                action("Get") { coordinator.installFromStore(entry) }
            case .update:
                action("Update") { coordinator.installFromStore(entry) }
            case .installed:
                Button("Open") { coordinator.selectExtension(entry.id) }.buttonStyle(.bordered)
            case .included:
                Text("Included").font(.callout).foregroundStyle(.secondary)
            case .developing:
                Text("In development").font(.callout).foregroundStyle(.secondary)
            case .needsApp(let version):
                Text(version.isEmpty ? "Needs a newer NotchNotch" : "Needs NotchNotch \(version)")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder private func action(_ title: String, _ perform: @escaping () -> Void) -> some View {
        if prominent {
            Button(title, action: perform).buttonStyle(.borderedProminent).disabled(coordinator.busy)
        } else {
            Button(title, action: perform).buttonStyle(.bordered).disabled(coordinator.busy)
        }
    }
}

/// An extension's page in the Store: what it is, what it can do, and the button.
struct StoreEntryPage: View {
    @Bindable var coordinator: ManagementCoordinator
    let entry: ExtensionCatalog.Entry
    @State private var readme: String?
    @State private var changelog: String?
    private var installed: InstalledExtension? { coordinator.model.installedExtensions.first { $0.id == entry.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { coordinator.destination = .store } label: { Label("Store", systemImage: "chevron.left") }
                    .buttonStyle(.link)
                HStack(alignment: .top, spacing: 16) {
                    StoreIcon(entry: entry, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.manifest.name).font(.title).bold()
                        Text(entry.author).foregroundStyle(.secondary)
                        Text(details).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StoreActionButton(coordinator: coordinator, entry: entry, prominent: true)
                }
                if let screenshots = entry.screenshots, !screenshots.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(screenshots, id: \.self) { url in
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8).fill(.quaternary).aspectRatio(16 / 10, contentMode: .fit)
                                }
                                .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                if let description = entry.manifest.description { Text(description) }
                if let readme { MarkdownView(readme) }
                Divider()
                ExtensionPermissionsView(manifest: entry.manifest, previous: installed?.manifest)
                if let changelog {
                    Divider()
                    Text("Version History").font(.title3).bold()
                    MarkdownView(changelog)
                }
                if ExtensionAboutRows.hasContent(entry.manifest) {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) { ExtensionAboutRows(manifest: entry.manifest) }.font(.callout)
                }
                Text(entry.id).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await loadDocuments() }
    }

    /// Fetched when the page opens. A missing or unreadable document is left
    /// out quietly: the page is still useful without it.
    private func loadDocuments() async {
        guard let client = coordinator.model.store.client else { return }
        async let readme = entry.readme.asyncMap { try? await client.document($0) }
        async let changelog = entry.changelog.asyncMap { try? await client.document($0) }
        (self.readme, self.changelog) = await (readme ?? nil, changelog ?? nil)
    }

    private var details: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(entry.package.size), countStyle: .file)
        return "Version \(entry.manifest.version) · \(size) · \(entry.published.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// A Store extension's icon from the catalog, or its SF Symbol.
struct StoreIcon: View {
    let entry: ExtensionCatalog.Entry
    let size: CGFloat
    var body: some View {
        if let url = entry.icon {
            AsyncImage(url: url) { image in
                image.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: size * 0.2).fill(.quaternary)
            }.frame(width: size, height: size).accessibilityHidden(true)
        } else {
            let symbol = entry.manifest.icon.flatMap { $0.hasSuffix(".png") ? nil : $0 } ?? ExtensionIcon.fallbackSymbol
            ExtensionIdentityView(icon: .symbol(symbol), size: size)
        }
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
