import NotchExtensions

enum ManagementSheet: Identifiable {
    /// A package to review; `store` is its catalog entry when it came from the Store.
    case install(ExtensionPackage, store: ExtensionCatalog.Entry?)
    case remove(InstalledExtension)
    var id: String {
        switch self {
        case .install(let package, _): "install:" + package.id
        case .remove(let record): "remove:" + record.id
        }
    }
}
