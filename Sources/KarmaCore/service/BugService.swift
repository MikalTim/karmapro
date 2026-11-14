// by cipher.org.uk
import Foundation

/// The security bug tracker as every front end uses it. The rules come from
/// `BugListWindowController` (columns, search, count text, backup and import)
/// and `BugEditorWindowController` (fields, defaults, validation); the windows
/// themselves are not reproduced here.
public enum BugService {

    // MARK: - Data transfer objects

    /// One bug report, with the display texts the list and detail show.
    public struct BugDTO: Codable, Sendable {
        public var id: String
        public var title: String
        public var severity: String
        public var exploitability: String
        public var detail: String
        public var packageName: String
        public var version: String
        public var status: String
        public var createdAt: Date
        /// The creation time as the list and detail show it ("MMM d, yyyy HH:mm").
        public var createdText: String
        /// The first eight characters of the id (the ID column).
        public var shortID: String
        /// The Package column: "—" without a package, else the name followed by " v<version>" when a version is set.
        public var packageText: String
        /// Set only by the code scanners; reports created in the app have none.
        public var filePath: String?
        public var line: Int?

        public init(id: String, title: String, severity: String, exploitability: String, detail: String,
                    packageName: String, version: String, status: String, createdAt: Date, createdText: String,
                    shortID: String, packageText: String, filePath: String?, line: Int?) {
            self.id = id
            self.title = title
            self.severity = severity
            self.exploitability = exploitability
            self.detail = detail
            self.packageName = packageName
            self.version = version
            self.status = status
            self.createdAt = createdAt
            self.createdText = createdText
            self.shortID = shortID
            self.packageText = packageText
            self.filePath = filePath
            self.line = line
        }
    }

    /// The fields the editor collects. Create and update take the same shape.
    public struct BugInputDTO: Codable, Sendable {
        public var title: String
        public var severity: String
        public var exploitability: String
        public var detail: String
        public var packageName: String
        public var version: String
        public var status: String

        public init(title: String, severity: String, exploitability: String, detail: String,
                    packageName: String, version: String, status: String) {
            self.title = title
            self.severity = severity
            self.exploitability = exploitability
            self.detail = detail
            self.packageName = packageName
            self.version = version
            self.status = status
        }
    }

    /// One table column in the order the list shows it. The bug list has no sort keys.
    public struct BugColumnDTO: Codable, Sendable {
        public var id: String
        public var title: String
        public var width: Double

        public init(id: String, title: String, width: Double) {
            self.id = id
            self.title = title
            self.width = width
        }
    }

    /// The bug list: every report matching the search, newest first.
    public struct BugListDTO: Codable, Sendable {
        public var bugs: [BugDTO]
        /// Reports with status "Open" or "In Progress" (all reports, not only the matches).
        public var openCount: Int
        /// The list's count line: "1 bug" or "N bugs" (matches only).
        public var countText: String
        public var columns: [BugColumnDTO]

        public init(bugs: [BugDTO], openCount: Int, countText: String, columns: [BugColumnDTO]) {
            self.bugs = bugs
            self.openCount = openCount
            self.countText = countText
            self.columns = columns
        }
    }

    /// A preset title for the editor's title menu, with the description it fills in.
    public struct BugPresetDTO: Codable, Sendable {
        public var title: String
        /// Nil for a preset without a description; the editor then keeps the current description.
        public var description: String?

        public init(title: String, description: String?) {
            self.title = title
            self.description = description
        }
    }

    /// Everything the editor offers: the popup choices, the preset titles and the values a new report starts with.
    public struct BugChoicesDTO: Codable, Sendable {
        public var severities: [String]
        public var statuses: [String]
        public var presets: [BugPresetDTO]
        /// The values a new report starts with: severity and exploitability are the first popup items ("info"), status is "Open".
        public var defaults: BugInputDTO

        public init(severities: [String], statuses: [String], presets: [BugPresetDTO], defaults: BugInputDTO) {
            self.severities = severities
            self.statuses = statuses
            self.presets = presets
            self.defaults = defaults
        }
    }

    /// The outcome of an import. `found` is the number of reports in the file; `added` is how many were new.
    public struct BugImportResultDTO: Codable, Sendable {
        public var added: Int
        public var found: Int
        /// True when the file was password protected.
        public var encrypted: Bool

        public init(added: Int, found: Int, encrypted: Bool) {
            self.added = added
            self.found = found
            self.encrypted = encrypted
        }
    }

    /// Import failures a front end must answer differently.
    public enum ImportError: LocalizedError {
        /// The file is encrypted and no password was given (the web answers 422 with `needsPassword`).
        case needsPassword
        case wrongPassword
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .needsPassword:
                return "This backup is encrypted. Enter its password to import it."
            case .wrongPassword:
                return BackupError.wrongPassword.errorDescription
            case .failed(let message):
                return message
            }
        }
    }

    // MARK: - State

    private static let lock = NSLock()

    /// The store the service works on. Nil uses `BugStore.shared`, the store the
    /// windows use; tests point it at a store in a temporary folder.
    static var storeOverride: BugStore?

    private static var store: BugStore { storeOverride ?? BugStore.shared }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy HH:mm"
        return formatter
    }()

    private static let columns: [BugColumnDTO] = [
        BugColumnDTO(id: "id", title: "ID", width: 150),
        BugColumnDTO(id: "title", title: "Title", width: 260),
        BugColumnDTO(id: "severity", title: "Severity", width: 90),
        BugColumnDTO(id: "exploitability", title: "Exploitability", width: 105),
        BugColumnDTO(id: "package", title: "Package", width: 150),
        BugColumnDTO(id: "status", title: "Status", width: 90),
        BugColumnDTO(id: "created", title: "Created", width: 140),
    ]

    private static let backupFileName = "KarmaProBugBackup.karmapro"

    private static func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Reports

    /// The reports matching `query` (the list window's search), with the list's counts and columns.
    public static func list(query: String) -> BugListDTO {
        locked {
            store.reload()
            let bugs = store.search(query)
            let count = bugs.count
            return BugListDTO(bugs: bugs.map { makeDTO($0) },
                              openCount: store.openBugCount,
                              countText: "\(count) bug\(count == 1 ? "" : "s")",
                              columns: columns)
        }
    }

    public static func get(id: String) throws -> BugDTO {
        try locked {
            guard let bug = store.bug(id: id) else {
                throw KarmaServiceError.notFound("The bug report no longer exists.")
            }
            return makeDTO(bug)
        }
    }

    /// Creates a report. Throws `invalid` with the editor's message when the title is blank.
    public static func create(_ input: BugInputDTO) throws -> BugDTO {
        try locked {
            let bug = try makeBug(id: UUID().uuidString, createdAt: Date(), filePath: nil, line: nil, from: input)
            store.add(bug)
            return makeDTO(bug)
        }
    }

    /// Replaces the editable fields of a report. The id, creation time, file path and line are kept.
    public static func update(id: String, _ input: BugInputDTO) throws -> BugDTO {
        try locked {
            guard let existing = store.bug(id: id) else {
                throw KarmaServiceError.notFound("The bug report no longer exists.")
            }
            let bug = try makeBug(id: existing.id, createdAt: existing.createdAt,
                                  filePath: existing.filePath, line: existing.line, from: input)
            store.update(bug)
            return makeDTO(bug)
        }
    }

    public static func delete(id: String) throws {
        try locked {
            guard store.bug(id: id) != nil else {
                throw KarmaServiceError.notFound("The bug report no longer exists.")
            }
            store.delete(id: id)
        }
    }

    /// The editor's popup choices, preset titles and new-report defaults.
    public static func choices() -> BugChoicesDTO {
        let presets = BugPresets.titles.map {
            BugPresetDTO(title: $0, description: BugPresets.descriptions[$0])
        }
        let defaults = BugInputDTO(title: "", severity: "info", exploitability: "info", detail: "",
                                   packageName: "", version: "", status: "Open")
        return BugChoicesDTO(severities: Bug.severityLevels, statuses: Bug.statuses,
                             presets: presets, defaults: defaults)
    }

    // MARK: - Backup and import

    /// Writes every report as the window does: JSON, encrypted when `password` is given.
    /// Nil means no encryption; an empty password is rejected as the window rejects a blank one.
    public static func backup(password: String?) throws -> (fileName: String, data: Data) {
        try locked {
            if let password, password.isEmpty {
                throw KarmaServiceError.invalid("The passwords did not match or were blank. No backup was saved.")
            }
            let json = try JSONEncoder().encode(store.allBugs())
            let data = try password.map { try BackupCrypto.seal(json, password: $0) } ?? json
            return (backupFileName, data)
        }
    }

    /// Merges the reports in a backup file, skipping ids that already exist. An encrypted
    /// file needs `password`; without it the call throws `ImportError.needsPassword`.
    public static func importBackup(data: Data, password: String?) throws -> BugImportResultDTO {
        try locked {
            let encrypted = BackupCrypto.isEncrypted(data)
            var plain = data
            if encrypted {
                guard let password, !password.isEmpty else { throw ImportError.needsPassword }
                do {
                    plain = try BackupCrypto.open(data, password: password)
                } catch BackupError.wrongPassword {
                    throw ImportError.wrongPassword
                } catch {
                    throw ImportError.failed(error.localizedDescription)
                }
            }
            let imported: [Bug]
            do {
                imported = try JSONDecoder().decode([Bug].self, from: plain)
            } catch {
                throw ImportError.failed("Could not read the backup file: \(error.localizedDescription)")
            }
            let added = imported.isEmpty ? 0 : store.merge(imported)
            return BugImportResultDTO(added: added, found: imported.count, encrypted: encrypted)
        }
    }

    // MARK: - Helpers

    /// Checks the editor's rules and builds the stored report.
    private static func makeBug(id: String, createdAt: Date, filePath: String?, line: Int?,
                                from input: BugInputDTO) throws -> Bug {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw KarmaServiceError.invalid("A title is required.")
        }
        guard Bug.severityLevels.contains(input.severity) else {
            throw KarmaServiceError.invalid("Unknown severity \"\(input.severity)\".")
        }
        guard Bug.severityLevels.contains(input.exploitability) else {
            throw KarmaServiceError.invalid("Unknown exploitability \"\(input.exploitability)\".")
        }
        guard Bug.statuses.contains(input.status) else {
            throw KarmaServiceError.invalid("Unknown status \"\(input.status)\".")
        }
        return Bug(id: id,
                   title: title,
                   severity: input.severity,
                   exploitability: input.exploitability,
                   detail: input.detail,
                   packageName: input.packageName.trimmingCharacters(in: .whitespacesAndNewlines),
                   version: input.version.trimmingCharacters(in: .whitespacesAndNewlines),
                   status: input.status,
                   createdAt: createdAt,
                   filePath: filePath,
                   line: line)
    }

    private static func makeDTO(_ bug: Bug) -> BugDTO {
        let version = bug.version.isEmpty ? "" : " v\(bug.version)"
        let package = (bug.packageName.isEmpty ? "—" : bug.packageName) + version
        return BugDTO(id: bug.id,
                      title: bug.title,
                      severity: bug.severity,
                      exploitability: bug.exploitability,
                      detail: bug.detail,
                      packageName: bug.packageName,
                      version: bug.version,
                      status: bug.status,
                      createdAt: bug.createdAt,
                      createdText: dateFormatter.string(from: bug.createdAt),
                      shortID: String(bug.id.prefix(8)),
                      packageText: package,
                      filePath: bug.filePath,
                      line: bug.line)
    }
}
