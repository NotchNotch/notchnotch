/// Which of the extensions that ship inside the app are installed.
public enum IncludedExtensions {
    /// Installs each extension in `introduced` once, for everyone, the first
    /// time an app that includes it runs, then remembers it in `offered`, so
    /// uninstalling it afterwards sticks.
    public static func introduce(_ introduced: Set<String>, available: Set<String>,
                                 installed: inout Set<String>, offered: inout Set<String>) {
        let fresh = introduced.intersection(available).subtracting(offered)
        installed.formUnion(fresh)
        offered.formUnion(fresh)
    }
}
