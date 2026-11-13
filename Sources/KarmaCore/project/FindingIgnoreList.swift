import Foundation

/// The findings a user has hidden with "Ignore issue". The set is stored in
/// UserDefaults as an array of keys (`"<path>#<line>"`), so a finding stays
/// hidden across launches. Each front end passes its own defaults key.
struct FindingIgnoreList {
    let defaultsKey: String
    let defaults: UserDefaults

    init(defaultsKey: String, defaults: UserDefaults = .standard) {
        self.defaultsKey = defaultsKey
        self.defaults = defaults
    }

    /// The stored keys. Reads UserDefaults on every access, as the window always did.
    var keys: Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    /// Builds a stable key identifying a single finding across scans.
    static func key(for f: ScanFinding) -> String {
        "\(f.fileURL.path)#\(f.line)"
    }

    /// Adds the finding to the stored set.
    func ignore(_ f: ScanFinding) {
        store(keys.union([Self.key(for: f)]))
    }

    /// Removes the finding from the stored set.
    func unignore(_ f: ScanFinding) {
        store(keys.subtracting([Self.key(for: f)]))
    }

    /// Removes findings the user has ignored, based on persisted (file, line) keys.
    func apply(_ input: [ScanFinding]) -> [ScanFinding] {
        let ignored = keys
        guard !ignored.isEmpty else { return input }
        return input.filter { !ignored.contains(Self.key(for: $0)) }
    }

    private func store(_ keys: Set<String>) {
        defaults.set(Array(keys), forKey: defaultsKey)
    }
}
