// by cipher.org.uk
import Foundation

/// Global private wiki. Pages are rich-text documents (RTF) stored under
/// `~/Library/Application Support/Karma Pro/Wiki/` and shared across all
/// projects. A `manifest.json` keeps title/slug and timestamps; the pages
/// themselves live in a `pages/` subdirectory as `<slug>.rtf`.
///
/// Backups are written as a `.karmawiki` archive (zip of the manifest and
/// page files), optionally encrypted with `BackupCrypto` when a password is
/// given. Imports accept an (optionally encrypted) archive or a plain folder
/// containing `manifest.json`/`pages` or bare `.rtf` files.
final class WikiStore {
    static let shared = WikiStore()

    struct PageInfo: Codable, Equatable {
        var slug: String
        var title: String
        var created: Double
        var updated: Double
    }

    enum WikiError: LocalizedError {
        case noManifest
        case corruptData
        case invalidArchive
        case toolMissing
        case importFailed(String)
        var errorDescription: String? {
            switch self {
            case .noManifest: return "The archive or folder contains no wiki manifest."
            case .corruptData: return "The wiki data is corrupted or unreadable."
            case .invalidArchive: return "The selected file is not a valid wiki archive."
            case .toolMissing: return "The \"zip\" and \"unzip\" command-line tools are required for wiki backups. Install them (for example: sudo apt install zip unzip)."
            case .importFailed(let m): return m
            }
        }
    }

    enum Conflict: String, Codable {
        case overwrite, rename, skip
    }

    let wikiDir: URL
    let pagesDir: URL
    private let manifestURL: URL

    private var manifest: [String: PageInfo] = [:]

    /// `directory` is where the wiki lives; nil uses the application support
    /// folder (tests pass a temporary one).
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Karma Pro", isDirectory: true)
            .appendingPathComponent("Wiki", isDirectory: true)
        wikiDir = base
        pagesDir = base.appendingPathComponent("pages", isDirectory: true)
        manifestURL = base.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)
        loadManifest()
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([PageInfo].self, from: data) {
            manifest = Dictionary(uniqueKeysWithValues: list.map { ($0.slug, $0) })
        }
    }

    private func saveManifest() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let list = manifest.values.sorted { $0.slug < $1.slug }
        if let data = try? encoder.encode(list) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    /// Enumerates the pages directory so pages added out-of-band (e.g. by a
    /// previous import) appear even when the manifest was empty.
    private func rescanFiles() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: pagesDir, includingPropertiesForKeys: nil)
        else { return }
        for url in urls where url.pathExtension == "rtf" {
            let slug = url.deletingPathExtension().lastPathComponent
            if manifest[slug] == nil {
                manifest[slug] = PageInfo(slug: slug,
                                          title: titleFromSlug(slug),
                                          created: Date().timeIntervalSince1970,
                                          updated: Date().timeIntervalSince1970)
            }
        }
    }

    private func titleFromSlug(_ slug: String) -> String {
        slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    // MARK: - Page access

    /// All pages, newest first.
    func allPages() -> [PageInfo] {
        rescanFiles()
        return manifest.values.sorted { $0.updated > $1.updated }
    }

    func pageInfo(slug: String) -> PageInfo? {
        manifest[slug]
    }

    /// Resolves a link target (a page name or slug as typed by the user) to
    /// the stored page. Matches either the slug or the title, case-insensitively.
    func resolve(_ target: String) -> String? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        rescanFiles()
        let folded = fold(trimmed)
        let slugged = slugify(trimmed)
        if manifest[slugged] != nil { return slugged }
        for (slug, info) in manifest where fold(info.title) == folded {
            return slug
        }
        return nil
    }

    func pageURL(slug: String) -> URL {
        pagesDir.appendingPathComponent(slug).appendingPathExtension("rtf")
    }

    /// Loads the rich-text body of a page as RTF bytes. Returns nil if the page
    /// is missing.
    func bodyRTF(slug: String) -> Data? {
        try? Data(contentsOf: pageURL(slug: slug))
    }

    /// Turns RTF bytes into searchable plain text. The AppKit app installs a
    /// Cocoa-based extractor at launch; everything else uses `WikiRTF`.
    static var plainTextExtractor: (Data) -> String = WikiRTF.plainText

    func bodyPlain(slug: String) -> String {
        Self.plainTextExtractor(bodyRTF(slug: slug) ?? Data())
    }

    // MARK: - Page mutations

    /// Creates a page from an RTF body. `title` is used to derive the slug when
    /// `slug` is not provided. Returns the slug of the stored page.
    @discardableResult
    func createPage(title: String, bodyRTF: Data, slug: String? = nil) -> String {
        rescanFiles()
        let now = Date().timeIntervalSince1970
        let finalSlug = slug ?? uniqueSlug(from: title)
        manifest[finalSlug] = PageInfo(slug: finalSlug, title: title.title, created: now, updated: now)
        writeBody(bodyRTF, slug: finalSlug)
        saveManifest()
        return finalSlug
    }

    /// Overwrites the body (and title) of an existing page. Returns false if
    /// the page does not exist.
    @discardableResult
    func savePage(slug: String, title: String, bodyRTF: Data) -> Bool {
        guard manifest[slug] != nil else { return false }
        var info = manifest[slug]!
        info.title = title.title
        info.updated = Date().timeIntervalSince1970
        manifest[slug] = info
        writeBody(bodyRTF, slug: slug)
        saveManifest()
        return true
    }

    private func writeBody(_ rtf: Data, slug: String) {
        try? rtf.write(to: pageURL(slug: slug), options: .atomic)
    }

    @discardableResult
    func deletePage(slug: String) -> Bool {
        rescanFiles()
        guard manifest.removeValue(forKey: slug) != nil else { return false }
        try? FileManager.default.removeItem(at: pageURL(slug: slug))
        saveManifest()
        return true
    }

    /// Renames a page, moving its file and rewriting the slug. Links that point
    /// at the old name are not rewritten (resolution falls back to matching by
    /// title via `resolve`). Returns the new slug, or nil on conflict/failure.
    func renamePage(slug: String, newTitle: String) -> String? {
        rescanFiles()
        guard var info = manifest[slug] else { return nil }
        let newSlug = uniqueSlug(from: newTitle, excluding: slug)
        info.slug = newSlug
        info.title = newTitle.title
        info.updated = Date().timeIntervalSince1970
        manifest.removeValue(forKey: slug)
        manifest[newSlug] = info

        let oldURL = pageURL(slug: slug)
        let newURL = pageURL(slug: newSlug)
        if FileManager.default.fileExists(atPath: oldURL.path) {
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
        }
        saveManifest()
        return newSlug
    }

    /// Builds a unique slug for a title. If the title already exists (or slug
    /// was not given), a numeric suffix is appended.
    func uniqueSlug(from title: String, excluding: String? = nil) -> String {
        rescanFiles()
        var base = slugify(title)
        if base.isEmpty { base = "untitled" }
        if base == excluding {
            return base
        }
        if manifest[base] == nil { return base }
        var candidate = base
        var n = 2
        while true {
            candidate = "\(base)-\(n)"
            if manifest[candidate] == nil { return candidate }
            n += 1
        }
    }

    /// Lowercases and normalises identifiers/titles without changing language.
    private func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts an arbitrary page name into a filesystem-safe slug.
    func slugify(_ s: String) -> String {
        let folded = fold(s)
        var result = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                result.append(ch.lowercased())
            } else {
                result.append("-")
            }
        }
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result
    }

    // MARK: - Search

    func search(_ query: String) -> [PageInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allPages() }
        let folded = fold(trimmed)
        return allPages().filter { info in
            if fold(info.title).contains(folded) { return true }
            return fold(bodyPlain(slug: info.slug)).contains(folded)
        }
    }

    // MARK: - Backup / import

    /// Writes a `.karmawiki` archive. When `password` is non-nil the archive is
    /// encrypted with `BackupCrypto` before being written. Returns pages written.
    @discardableResult
    func backup(to url: URL, password: String?) throws -> Int {
        rescanFiles()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("karmawiki-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let pagesURL = temp.appendingPathComponent("pages", isDirectory: true)
        try FileManager.default.createDirectory(at: pagesURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let list = manifest.values.sorted { $0.slug < $1.slug }
        let manifestData = try encoder.encode(list)
        try manifestData.write(to: temp.appendingPathComponent("manifest.json"))

        for info in list {
            if FileManager.default.fileExists(atPath: pageURL(slug: info.slug).path) {
                try? FileManager.default.copyItem(at: pageURL(slug: info.slug),
                                                  to: pagesURL.appendingPathComponent(info.slug + ".rtf"))
            }
        }

        let zipURL = temp.appendingPathComponent("wiki.karmawiki")
        try WikiZip.zip(directory: temp, to: zipURL)
        var bytes = try Data(contentsOf: zipURL)
        if let password = password, !password.isEmpty {
            bytes = try BackupCrypto.seal(bytes, password: password)
        }
        try bytes.write(to: url, options: .atomic)
        return list.count
    }

    /// Restores pages from a `.karmawiki` archive or a plain folder (pages/
    /// + manifest.json, or bare .rtf files). `password` is required when the
    /// archive is encrypted. Conflicts are resolved through `onConflict`.
    /// Returns (imported, overwritten, renamed, skipped) counts.
    func `import`(from url: URL, password: String?, onConflict: (String) -> Conflict) throws -> (imported: Int, overwritten: Int, renamed: Int, skipped: Int) {
        let source = try unpackImport(from: url, password: password)
        defer { source.cleanup() }
        return try importFromFolder(source.folder, onConflict: onConflict)
    }

    /// The slugs an import of `url` would find already present in the wiki, in
    /// the order `import` asks about them. Front ends that cannot answer
    /// `onConflict` synchronously (the web UI) ask the user first, then call
    /// `import` with the answers.
    func importConflicts(from url: URL, password: String?) throws -> [String] {
        let source = try unpackImport(from: url, password: password)
        defer { source.cleanup() }
        rescanFiles()
        let content = try readImportFolder(source.folder)
        return content.pending.keys.sorted().filter { manifest[$0] != nil }
    }

    /// Decrypts and unzips an archive into a temporary folder (or returns the
    /// folder itself when `url` is a directory).
    private func unpackImport(from url: URL, password: String?) throws -> (folder: URL, cleanup: () -> Void) {
        if url.hasDirectoryPath {
            return (url, {})
        }
        var bytes = try Data(contentsOf: url)

        if BackupCrypto.isEncrypted(bytes) {
            guard let pw = password, !pw.isEmpty else {
                throw BackupError.wrongPassword
            }
            bytes = try BackupCrypto.open(bytes, password: pw)
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("karmawiki-import-\(UUID().uuidString)", isDirectory: true)
        let cleanup = { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let zipURL = temp.appendingPathComponent("blob.karmawiki")
        do {
            try bytes.write(to: zipURL)
            guard try WikiZip.unzip(zipURL: zipURL, into: temp) else {
                throw WikiError.invalidArchive
            }
        } catch {
            cleanup()
            throw error
        }
        return (temp, { cleanup() })
    }

    /// Reads the pages found in an unpacked backup folder.
    private func readImportFolder(_ folder: URL) throws -> (pending: [String: PageInfo], pageURLs: [String: URL]) {
        var pending: [String: PageInfo] = [:]
        var pageURLs: [String: URL] = [:]

        let manifestFile = folder.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestFile),
           let list = try? JSONDecoder().decode([PageInfo].self, from: data) {
            pending = Dictionary(list.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        }

        var pagesFolder = folder.appendingPathComponent("pages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: pagesFolder.path) {
            pagesFolder = folder
        }
        if let urls = try? FileManager.default.contentsOfDirectory(at: pagesFolder, includingPropertiesForKeys: nil) {
            for url in urls where url.pathExtension == "rtf" {
                let slug = url.deletingPathExtension().lastPathComponent
                if pending[slug] == nil {
                    pending[slug] = PageInfo(slug: slug,
                                             title: titleFromSlug(slug),
                                             created: Date().timeIntervalSince1970,
                                             updated: Date().timeIntervalSince1970)
                }
                pageURLs[slug] = url
            }
        }

        guard !pending.isEmpty else { throw WikiError.noManifest }
        return (pending, pageURLs)
    }

    private func importFromFolder(_ folder: URL, onConflict: (String) -> Conflict) throws -> (imported: Int, overwritten: Int, renamed: Int, skipped: Int) {
        rescanFiles()
        var result = (imported: 0, overwritten: 0, renamed: 0, skipped: 0)
        let content = try readImportFolder(folder)

        for slug in content.pending.keys.sorted() {
            let info = content.pending[slug]!
            let loaded: Data
            if let bodyURL = content.pageURLs[slug], let data = try? Data(contentsOf: bodyURL) {
                loaded = data
            } else {
                loaded = WikiRTF.encode(WikiDocument(plain: info.title))
            }

            if manifest[slug] != nil {
                switch onConflict(slug) {
                case .overwrite:
                    manifest[slug] = info
                    writeBody(loaded, slug: slug)
                    result.overwritten += 1
                case .rename:
                    let newSlug = uniqueSlug(from: info.title)
                    manifest[newSlug] = PageInfo(slug: newSlug, title: info.title,
                                                 created: info.created, updated: info.updated)
                    writeBody(loaded, slug: newSlug)
                    result.renamed += 1
                case .skip:
                    result.skipped += 1
                }
            } else {
                manifest[slug] = info
                writeBody(loaded, slug: slug)
                result.imported += 1
            }
        }
        saveManifest()
        return result
    }
}

/// Minimal zip/unzip helpers around the system tools. Used by `WikiStore` so
/// backups round-trip without pulling in a third-party archive dependency.
/// The tools are found through `env`, so they work wherever they are installed
/// (`/usr/bin` on macOS, `/usr/bin` or `/bin` on Linux).
enum WikiZip {
    /// Runs `tool` and returns its exit status. Throws `WikiStore.WikiError.toolMissing`
    /// when the tool cannot be started or is not installed.
    private static func run(_ tool: String, _ arguments: [String], in directory: URL? = nil) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        process.currentDirectoryURL = directory
        // `env` prints "No such file or directory" for a missing tool; keep that off the terminal.
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw WikiStore.WikiError.toolMissing
        }
        process.waitUntilExit()
        if process.terminationStatus == 127 { throw WikiStore.WikiError.toolMissing }
        return process.terminationStatus
    }

    /// Zips the entire directory (relative paths preserved) into `to`.
    @discardableResult
    static func zip(directory: URL, to: URL) throws -> Bool {
        try? FileManager.default.removeItem(at: to)
        return try run("zip", ["-r", "-q", to.path, "."], in: directory) == 0
    }

    /// Extracts a zip archive into the destination directory.
    @discardableResult
    static func unzip(zipURL: URL, into: URL) throws -> Bool {
        try run("unzip", ["-q", "-o", zipURL.path, "-d", into.path]) == 0
    }
}

private extension String {
    /// Title-cases a string used as a page title (keeps the rest of the casing).
    var title: String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Untitled" }
        return prefix(1).uppercased() + dropFirst()
    }
}