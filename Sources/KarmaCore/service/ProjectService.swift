// by cipher.org.uk
import Foundation

/// One entry of the file tree.
public struct FileNodeDTO: Codable, Sendable {
    public var name: String
    /// Absolute path.
    public var path: String
    public var isDirectory: Bool
    /// "A" or "M" next to a file the open pull request adds or changes.
    public var badge: String?
    /// Nil for files and for search results.
    public var children: [FileNodeDTO]?
}

/// The file tree as the sidebar shows it.
public struct ProjectTreeDTO: Codable, Sendable {
    /// The (filtered) tree, shown with the project folder as its single top node. Nil when no project is open.
    /// Empty while `matches` is used.
    public var root: FileNodeDTO?
    /// Set when the search text is not empty: the flat list of every file and folder whose name contains it.
    public var matches: [FileNodeDTO]?
}

/// The main window's project features: opening a folder, the language list and the file tree.
public enum ProjectService {
    /// The names offered by the language popup, "All Languages" first.
    public static func languages() -> [String] {
        Language.supported.map(\.name)
    }

    /// `POST /api/project/open`: opens `path` and returns the index job's id.
    public static func open(path: String) throws -> String {
        try KarmaWorkspace.shared.open(root: path)
    }

    public static func info() -> ProjectInfoDTO {
        KarmaWorkspace.shared.info()
    }

    /// The tree for the sidebar (`FileTreeViewController`).
    ///
    /// - `language`: a name from `languages()`; "All Languages" or nil shows every file.
    /// - `query`: when not empty (after trimming), the result is the flat list of names that contain it,
    ///   searched over the whole project regardless of the language and pull request filters.
    ///
    /// During a pull request review the tree is pruned to the changed files first and the language filter is
    /// applied on top; "show all" lifts the pruning but keeps the language filter.
    public static func tree(language: String?, query: String?) throws -> ProjectTreeDTO {
        let selected = try languageNamed(language)
        let snapshot = KarmaWorkspace.shared.read { ($0.rootNode, $0.prChangedPaths, $0.showAllFiles, $0.changeBadges) }
        guard let root = snapshot.0 else { return ProjectTreeDTO(root: nil, matches: nil) }
        let badges = snapshot.3

        let trimmed = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            let matches = root.matchingFiles(query: trimmed).map { dto($0, badges: badges, recursive: false) }
            return ProjectTreeDTO(root: nil, matches: matches)
        }

        let shown: FileNode
        if let paths = snapshot.1, !snapshot.2 {
            // The pull request filter first, so the pruned tree only walks the few files it touched.
            let changed = root.filtered { FileNode.matchesPullRequest($0, paths: paths, root: root.url) }
            shown = selected.map { changed.filtered(language: $0) } ?? changed
        } else {
            shown = selected.map { root.filtered(language: $0) } ?? root
        }
        return ProjectTreeDTO(root: dto(shown, badges: badges, recursive: true), matches: nil)
    }

    private static func languageNamed(_ name: String?) throws -> Language? {
        guard let name, name != "All Languages", !name.isEmpty else { return nil }
        guard let language = Language.supported.first(where: { $0.name == name }) else {
            throw KarmaServiceError.invalid("Unknown language \"\(name)\".")
        }
        return language
    }

    private static func dto(_ node: FileNode, badges: [String: String], recursive: Bool) -> FileNodeDTO {
        // The badge is looked up by file name, as the AppKit cell does.
        let badge = node.isDirectory ? nil : badges[node.name]
        return FileNodeDTO(name: node.name,
                           path: node.url.path,
                           isDirectory: node.isDirectory,
                           badge: badge,
                           children: recursive && node.isDirectory
                               ? node.children.map { dto($0, badges: badges, recursive: true) }
                               : nil)
    }
}
