// by cipher.org.uk
import Foundation

/// The private wiki as every front end uses it. The rules come from
/// `WikiWindowController` (list, search, create, rename, delete, backup and the
/// import conflict flow) and `WikiEditorWindowController` (load, save, links),
/// without the windows.
public enum WikiService {

    // MARK: - Data transfer objects

    /// One page in the list and the page header.
    public struct WikiPageDTO: Codable, Sendable {
        public var slug: String
        public var title: String
        /// Seconds since 1970, as the store keeps them.
        public var created: Double
        public var updated: Double
        /// The created and updated times as the list shows them (medium date, short time).
        public var createdText: String
        public var updatedText: String

        public init(slug: String, title: String, created: Double, updated: Double,
                    createdText: String, updatedText: String) {
            self.slug = slug
            self.title = title
            self.created = created
            self.updated = updated
            self.createdText = createdText
            self.updatedText = updatedText
        }
    }

    /// The page list: pages matching the search, most recently updated first.
    public struct WikiListDTO: Codable, Sendable {
        public var pages: [WikiPageDTO]
        /// The list's count line: "1 page", "N pages", or "N pages matching \"query\"".
        public var statusText: String

        public init(pages: [WikiPageDTO], statusText: String) {
            self.pages = pages
            self.statusText = statusText
        }
    }

    /// A page with its body, as the editor loads it.
    public struct WikiPageDetailDTO: Codable, Sendable {
        public var info: WikiPageDTO
        public var document: WikiDocument

        public init(info: WikiPageDTO, document: WikiDocument) {
            self.info = info
            self.document = document
        }
    }

    /// An uploaded backup waiting for its conflict answers.
    public struct WikiImportSessionDTO: Codable, Sendable {
        public var importID: String
        /// Slugs that already exist in the wiki, in the order the import asks about them.
        public var conflicts: [String]
        /// The title of each conflicting page in the wiki (the text the conflict alert shows).
        public var conflictTitles: [String: String]

        public init(importID: String, conflicts: [String], conflictTitles: [String: String]) {
            self.importID = importID
            self.conflicts = conflicts
            self.conflictTitles = conflictTitles
        }
    }

    /// The outcome of an import, with the summary line the window shows.
    public struct WikiImportResultDTO: Codable, Sendable {
        public var imported: Int
        public var overwritten: Int
        public var renamed: Int
        public var skipped: Int
        /// "Imported: 1 new, 2 skipped." or "Nothing was imported.", as the window words it.
        public var summary: String

        public init(imported: Int, overwritten: Int, renamed: Int, skipped: Int, summary: String) {
            self.imported = imported
            self.overwritten = overwritten
            self.renamed = renamed
            self.skipped = skipped
            self.summary = summary
        }
    }

    /// Import failures a front end must answer differently.
    public enum ImportError: LocalizedError {
        /// The archive is encrypted and no password was given.
        case needsPassword
        case wrongPassword

        public var errorDescription: String? {
            switch self {
            case .needsPassword:
                return "This backup is encrypted. Enter its password to import it."
            case .wrongPassword:
                return BackupError.wrongPassword.errorDescription
            }
        }
    }

    // MARK: - State

    private static let lock = NSLock()

    /// The store the service works on. Nil uses `WikiStore.shared`, the store the
    /// windows use; tests point it at a store in a temporary folder.
    static var storeOverride: WikiStore?

    private static var store: WikiStore { storeOverride ?? WikiStore.shared }

    /// The current time. Tests move it forward to check the import expiry.
    static var clock: () -> Date = { Date() }

    /// How long an uploaded backup waits for its conflict answers.
    static let importLifetime: TimeInterval = 10 * 60

    private static let backupFileName = "KarmaProWiki.karmawiki"

    private struct PendingImport {
        let url: URL
        let expires: Date
    }

    private static var pendingImports: [String: PendingImport] = [:]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Pages

    /// Pages matching `query` (title or body), newest update first, with the window's count line.
    public static func list(query: String) -> WikiListDTO {
        locked {
            let pages = store.search(query)
            let count = pages.count
            let statusText = query.isEmpty
                ? (count == 1 ? "1 page" : "\(count) pages")
                : "\(count) page\(count == 1 ? "" : "s") matching \"\(query)\""
            return WikiListDTO(pages: pages.map { makePageDTO($0) }, statusText: statusText)
        }
    }

    /// Creates a page with an empty body. A blank title becomes "Untitled".
    /// Given a `slug` (a dead link being opened), the page takes that slug and, when the
    /// title is blank, a title derived from it; an existing slug is refused.
    public static func create(title: String, slug: String? = nil) throws -> WikiPageDTO {
        try locked {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let empty = WikiRTF.encode(WikiDocument())
            let finalSlug: String
            let finalTitle: String
            if let slug, !slug.isEmpty {
                guard store.pageInfo(slug: slug) == nil else {
                    throw KarmaServiceError.invalid("A page with that name already exists.")
                }
                finalSlug = slug
                finalTitle = trimmed.isEmpty ? titleFromSlug(slug) : trimmed
            } else {
                finalSlug = store.uniqueSlug(from: trimmed.isEmpty ? "Untitled" : trimmed)
                finalTitle = trimmed.isEmpty ? "Untitled" : trimmed
            }
            let created = store.createPage(title: finalTitle, bodyRTF: empty, slug: finalSlug)
            KarmaEventBus.shared.post("wiki.changed")
            guard let info = store.pageInfo(slug: created) else {
                throw KarmaServiceError.notFound("The page could not be created.")
            }
            return makePageDTO(info)
        }
    }

    /// A page with its body decoded from the stored RTF (an empty body when none is stored).
    public static func page(slug: String) throws -> WikiPageDetailDTO {
        try locked {
            guard let info = store.pageInfo(slug: slug) else {
                throw KarmaServiceError.notFound("The page no longer exists.")
            }
            let document = store.bodyRTF(slug: slug).map { WikiRTF.decode($0) } ?? WikiDocument()
            return WikiPageDetailDTO(info: makePageDTO(info), document: document)
        }
    }

    /// Stores the title and body of a page, the way the editor's save does.
    public static func save(slug: String, title: String, document: WikiDocument) throws {
        try locked {
            guard store.savePage(slug: slug, title: title, bodyRTF: WikiRTF.encode(document)) else {
                throw KarmaServiceError.notFound("The page no longer exists.")
            }
            KarmaEventBus.shared.post("wiki.changed")
        }
    }

    /// Renames a page and returns it under its new slug. A blank or unchanged title does nothing,
    /// as the window's rename does.
    public static func rename(slug: String, title: String) throws -> WikiPageDTO {
        try locked {
            guard let current = store.pageInfo(slug: slug) else {
                throw KarmaServiceError.notFound("The page no longer exists.")
            }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != current.title else {
                return makePageDTO(current)
            }
            guard let newSlug = store.renamePage(slug: slug, newTitle: trimmed),
                  let renamed = store.pageInfo(slug: newSlug) else {
                throw KarmaServiceError.invalid("The page could not be renamed.")
            }
            KarmaEventBus.shared.post("wiki.changed")
            return makePageDTO(renamed)
        }
    }

    public static func delete(slug: String) throws {
        try locked {
            guard store.deletePage(slug: slug) else {
                throw KarmaServiceError.notFound("The page no longer exists.")
            }
            KarmaEventBus.shared.post("wiki.changed")
        }
    }

    // MARK: - Links

    /// The slug of the page a link target (a name or slug as typed) refers to, or nil when there is none.
    /// The editor creates the page on a click when this returns nil.
    public static func resolve(target: String) -> String? {
        locked { store.resolve(target) }
    }

    /// The `wiki://page/<name>` link the editor inserts for a target name, or nil when it is not a valid URL.
    public static func linkURL(for target: String) -> String? {
        let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
        let text = "wiki://page/\(encoded)"
        return URL(string: text) == nil ? nil : text
    }

    /// The page name a `wiki://` link points at, or nil for any other link.
    public static func linkTarget(for link: String) -> String? {
        guard let url = URL(string: link), url.scheme == "wiki" else { return nil }
        let target = url.lastPathComponent.removingPercentEncoding ?? ""
        return target.isEmpty ? nil : target
    }

    // MARK: - Backup and import

    /// Writes every page as a `.karmawiki` archive, encrypted when `password` is given.
    /// Nil means no encryption; an empty password is rejected as the window rejects a blank one.
    /// Throws `WikiStore.WikiError.toolMissing` when `zip` is not installed.
    public static func backup(password: String?) throws -> (fileName: String, data: Data) {
        try locked {
            if let password, password.isEmpty {
                throw KarmaServiceError.invalid("The passwords did not match or were blank. No backup was saved.")
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("karmawiki-export-\(UUID().uuidString).karmawiki")
            defer { try? FileManager.default.removeItem(at: url) }
            try store.backup(to: url, password: password)
            return (backupFileName, try Data(contentsOf: url))
        }
    }

    /// Reads an uploaded backup and returns the conflicts that need an answer before it can be imported.
    /// An encrypted archive needs `password`; without it the call throws `ImportError.needsPassword`.
    /// The archive is kept for ten minutes under the returned `importID`.
    public static func beginImport(data: Data, password: String?) throws -> WikiImportSessionDTO {
        try locked {
            purgeExpiredImports()
            var bytes = data
            if BackupCrypto.isEncrypted(data) {
                guard let password, !password.isEmpty else { throw ImportError.needsPassword }
                do {
                    bytes = try BackupCrypto.open(data, password: password)
                } catch BackupError.wrongPassword {
                    throw ImportError.wrongPassword
                }
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("karmawiki-upload-\(UUID().uuidString).karmawiki")
            try bytes.write(to: url, options: .atomic)
            let conflicts: [String]
            do {
                conflicts = try store.importConflicts(from: url, password: nil)
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
            let id = UUID().uuidString
            pendingImports[id] = PendingImport(url: url, expires: clock().addingTimeInterval(importLifetime))
            var titles: [String: String] = [:]
            for slug in conflicts {
                titles[slug] = store.pageInfo(slug: slug)?.title ?? slug
            }
            return WikiImportSessionDTO(importID: id, conflicts: conflicts, conflictTitles: titles)
        }
    }

    /// Imports an uploaded archive with the answers to its conflicts. A slug without an answer,
    /// or with an unknown answer, is skipped. Throws `notFound` when the upload has expired.
    public static func finishImport(importID: String, decisions: [String: String]) throws -> WikiImportResultDTO {
        try locked {
            purgeExpiredImports()
            guard let pending = pendingImports.removeValue(forKey: importID) else {
                throw expiredImportError
            }
            defer { try? FileManager.default.removeItem(at: pending.url) }
            let result = try store.import(from: pending.url, password: nil) { slug in
                decisions[slug].flatMap(WikiStore.Conflict.init(rawValue:)) ?? .skip
            }
            KarmaEventBus.shared.post("wiki.changed")
            let parts: [String] = [
                result.imported > 0 ? "\(result.imported) new" : nil,
                result.overwritten > 0 ? "\(result.overwritten) overwritten" : nil,
                result.renamed > 0 ? "\(result.renamed) renamed" : nil,
                result.skipped > 0 ? "\(result.skipped) skipped" : nil,
            ].compactMap { $0 }
            return WikiImportResultDTO(
                imported: result.imported,
                overwritten: result.overwritten,
                renamed: result.renamed,
                skipped: result.skipped,
                summary: parts.isEmpty ? "Nothing was imported." : "Imported: " + parts.joined(separator: ", ") + "."
            )
        }
    }

    // MARK: - Helpers

    private static var expiredImportError: KarmaServiceError {
        KarmaServiceError.notFound("The import expired; upload the file again.")
    }

    /// Removes uploads whose time is up and deletes their temporary files. Call under `lock`.
    private static func purgeExpiredImports() {
        let now = clock()
        for (id, pending) in pendingImports where pending.expires <= now {
            try? FileManager.default.removeItem(at: pending.url)
            pendingImports.removeValue(forKey: id)
        }
    }

    private static func makePageDTO(_ info: WikiStore.PageInfo) -> WikiPageDTO {
        WikiPageDTO(slug: info.slug,
                    title: info.title,
                    created: info.created,
                    updated: info.updated,
                    createdText: dateFormatter.string(from: Date(timeIntervalSince1970: info.created)),
                    updatedText: dateFormatter.string(from: Date(timeIntervalSince1970: info.updated)))
    }

    /// The title the editor gives a page created from a slug (the window's `titleFromSlug`).
    private static func titleFromSlug(_ slug: String) -> String {
        slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}
