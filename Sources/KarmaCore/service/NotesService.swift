// by cipher.org.uk
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Notes window (`NotesWindowController`): every note of the open project,
/// with export and import of `.codenotes` files.
public enum NotesService {
    /// One row of the table.
    public struct NoteDTO: Codable, Sendable {
        /// Absolute path of the annotated file.
        public var path: String
        /// The path relative to the project folder, or the absolute path for a file outside it.
        public var relativePath: String
        /// The File column: the file name.
        public var file: String
        /// 1-based line.
        public var line: Int
        public var text: String

        public init(path: String, relativePath: String, file: String, line: Int, text: String) {
            self.path = path
            self.relativePath = relativePath
            self.file = file
            self.line = line
            self.text = text
        }
    }

    /// The window's table and its status line.
    public struct ListDTO: Codable, Sendable {
        /// Absolute path of the open project, or nil when none is open (then every note is listed).
        public var root: String?
        /// "No notes yet.", "1 note" or "N notes".
        public var statusText: String
        /// Sorted by path, then line, as the store returns them.
        public var notes: [NoteDTO]

        public init(root: String?, statusText: String, notes: [NoteDTO]) {
            self.root = root
            self.statusText = statusText
            self.notes = notes
        }
    }

    /// The outcome of an import, with the title and message of the alert the window shows.
    public struct ImportResultDTO: Codable, Sendable {
        /// Notes added or updated.
        public var count: Int
        /// "Imported" or "Import Failed".
        public var title: String
        public var message: String

        public init(count: Int, title: String, message: String) {
            self.count = count
            self.title = title
            self.message = message
        }
    }

    // MARK: - Public API

    /// `GET /api/notes`: the notes of the open project, or every note when no project is open.
    public static func list() -> ListDTO {
        list(store: .shared, root: openRoot())
    }

    /// `GET /api/notes/export`: the `.codenotes` file the window's export writes, named as its save panel names it.
    public static func export() throws -> (fileName: String, data: Data) {
        try export(store: .shared, root: openRoot())
    }

    /// `POST /api/notes/import`: merges an uploaded `.codenotes` or `.json` file.
    public static func importNotes(data: Data) -> ImportResultDTO {
        importData(store: .shared, root: openRoot(), data: data)
    }

    /// `POST /api/notes/import-url`: fetches a notes file from `urlString` and merges it. Returns the job id;
    /// its result is an `ImportResultDTO`.
    public static func importNotes(urlString: String) throws -> String {
        let raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else {
            throw KarmaServiceError.invalid("Enter a valid web address.")
        }
        return KarmaJobCenter.shared.start(kind: "notes-import-url") { _ in
            KarmaJSON.data(importFromURL(store: .shared, root: openRoot(), url: url))
        }
    }

    // MARK: - Internals

    static func list(store: NoteStore, root: URL?) -> ListDTO {
        let stored = root.map { store.notes(forProject: $0) } ?? store.allNotes()
        let rootPath = root?.standardizedFileURL.path
        let notes = stored.map { note in
            NoteDTO(path: note.path,
                    relativePath: relativePath(of: note.path, rootPath: rootPath),
                    file: (note.path as NSString).lastPathComponent,
                    line: note.line,
                    text: note.text)
        }
        let status: String
        if notes.isEmpty {
            status = "No notes yet."
        } else {
            status = "\(notes.count) note\(notes.count == 1 ? "" : "s")"
        }
        return ListDTO(root: root?.path, statusText: status, notes: notes)
    }

    /// Writes the store's `.codenotes` file through a temporary file, as the window's export does.
    static func export(store: NoteStore, root: URL?) throws -> (fileName: String, data: Data) {
        let projectName = root?.lastPathComponent ?? "UnknownProject"
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-notes-\(UUID().uuidString).codenotes")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let written = store.export(to: temporary, projectRoot: root)
        guard written else {
            throw KarmaServiceError.invalid("Could not write the notes file.")
        }
        return ("\(projectName)-notes.codenotes", try Data(contentsOf: temporary))
    }

    static func importData(store: NoteStore, root: URL?, data: Data) -> ImportResultDTO {
        let result = store.importFrom(data: data, projectRoot: root)
        if result.count > 0 {
            KarmaEventBus.shared.post("notes.changed")
        }
        return outcome(result)
    }

    /// The window's `importURLClicked` after the request: the same checks and alert texts.
    static func importFromURL(store: NoteStore, root: URL?, url: URL) -> ImportResultDTO {
        let (data, response, error) = fetch(url)
        if let error {
            return ImportResultDTO(count: 0, title: "Import Failed", message: error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return ImportResultDTO(count: 0, title: "Import Failed", message: "Server returned HTTP \(http.statusCode).")
        }
        guard let data, !data.isEmpty else {
            return ImportResultDTO(count: 0, title: "Import Failed", message: "No data received.")
        }
        return importData(store: store, root: root, data: data)
    }

    /// The window's alert for an import result.
    static func outcome(_ result: (count: Int, error: String)) -> ImportResultDTO {
        if result.count > 0 {
            return ImportResultDTO(count: result.count, title: "Imported",
                                   message: "Merged \(result.count) note\(result.count == 1 ? "" : "s").")
        }
        if result.error.isEmpty {
            return ImportResultDTO(count: 0, title: "Imported", message: "No new notes to add.")
        }
        return ImportResultDTO(count: 0, title: "Import Failed", message: result.error)
    }

    /// The outcome of one request, written by the URLSession callback thread.
    private final class FetchOutcome: @unchecked Sendable {
        let lock = NSLock()
        var data: Data?
        var response: URLResponse?
        var error: Error?
    }

    private static func fetch(_ url: URL) -> (Data?, URLResponse?, Error?) {
        let semaphore = DispatchSemaphore(value: 0)
        let outcome = FetchOutcome()
        URLSession.shared.dataTask(with: url) { data, response, error in
            outcome.lock.lock()
            outcome.data = data
            outcome.response = response
            outcome.error = error
            outcome.lock.unlock()
            semaphore.signal()
        }.resume()
        semaphore.wait()
        outcome.lock.lock()
        defer { outcome.lock.unlock() }
        return (outcome.data, outcome.response, outcome.error)
    }

    private static func openRoot() -> URL? {
        KarmaWorkspace.shared.read { $0.root }
    }

    private static func relativePath(of path: String, rootPath: String?) -> String {
        guard let rootPath else { return path }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }
}
