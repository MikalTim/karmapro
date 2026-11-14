// by cipher.org.uk
import Foundation

/// The Search in Files window (`FileSearchWindowController`): a case-insensitive
/// search of every line of the open project's text files.
public enum SearchService {
    /// One matching line, in the order the window's table shows it.
    public struct MatchDTO: Codable, Sendable {
        /// Absolute path of the file.
        public var path: String
        /// The path relative to the project folder, for the file name shown in the row.
        public var relativePath: String
        /// 1-based line number.
        public var line: Int
        /// The whole line, without its line terminator.
        public var text: String

        public init(path: String, relativePath: String, line: Int, text: String) {
            self.path = path
            self.relativePath = relativePath
            self.line = line
            self.text = text
        }
    }

    /// The job result: the rows and the status line the window shows under its search field.
    public struct ResultDTO: Codable, Sendable {
        public var term: String
        /// "No matches", "N matches", or "No folder is open." when no project is open.
        public var statusText: String
        public var matches: [MatchDTO]

        public init(term: String, statusText: String, matches: [MatchDTO]) {
            self.term = term
            self.statusText = statusText
            self.matches = matches
        }
    }

    /// `POST /api/search`: starts a search of the open project and returns the job id.
    ///
    /// - `language`: a name from `ProjectService.languages()`; nil or "All Languages" searches every file.
    public static func search(term: String, language: String?) throws -> String {
        let selected = try languageNamed(language)
        return KarmaJobCenter.shared.start(kind: "search") { _ in
            let root = KarmaWorkspace.shared.read { $0.root }
            return KarmaJSON.data(result(term: term, root: root, language: selected))
        }
    }

    /// The window's search (`performSearch`): every match under `root`, with the status line the window builds.
    static func result(term: String, root: URL?, language: Language?) -> ResultDTO {
        guard let root else {
            return ResultDTO(term: term, statusText: "No folder is open.", matches: [])
        }
        let found = ProjectTextSearch.search(term: term, root: root, language: language, isCancelled: { false })
        let rootPath = root.standardizedFileURL.path
        let matches = found.map { match in
            MatchDTO(path: match.fileURL.path,
                     relativePath: relativePath(of: match.fileURL.path, rootPath: rootPath),
                     line: match.line,
                     text: match.text)
        }
        let status = matches.isEmpty
            ? "No matches"
            : "\(matches.count) match\(matches.count == 1 ? "" : "es")"
        return ResultDTO(term: term, statusText: status, matches: matches)
    }

    private static func relativePath(of path: String, rootPath: String) -> String {
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return (path as NSString).lastPathComponent
    }

    /// The language named in the popup, or nil for "All Languages".
    private static func languageNamed(_ name: String?) throws -> Language? {
        guard let name, name != "All Languages", !name.isEmpty else { return nil }
        guard let language = Language.supported.first(where: { $0.name == name }) else {
            throw KarmaServiceError.invalid("Unknown language \"\(name)\".")
        }
        return language
    }
}
