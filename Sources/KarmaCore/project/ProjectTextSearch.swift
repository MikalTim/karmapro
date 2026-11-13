// by cipher.org.uk
import Foundation

/// One line of a project file that contains a search term.
struct ProjectTextMatch {
    let fileURL: URL
    /// 1-based line number.
    let line: Int
    /// The whole line, without its line terminator.
    let text: String
}

/// Case-insensitive text search across the files of a project folder.
enum ProjectTextSearch {
    /// Returns every line of every searchable file under `root` that contains `term`.
    ///
    /// Hidden files are skipped, as are files with image, archive or bundle
    /// extensions. When `language` is set, only files of that language are read.
    /// `isCancelled` is polled before each file; when it returns true the search
    /// stops and the matches found so far are returned.
    static func search(term: String, root: URL, language: Language?, isCancelled: () -> Bool) -> [ProjectTextMatch] {
        guard !term.isEmpty else { return [] }
        var found: [ProjectTextMatch] = []
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: root,
                                          includingPropertiesForKeys: [.isRegularFileKey],
                                          options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if isCancelled() { break }
                if shouldSkip(url, language: language) { continue }
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let ns = contents as NSString
                let lines = ns.components(separatedBy: "\n")
                var lineNumber = 0
                for line in lines {
                    lineNumber += 1
                    let range = (line as NSString).range(of: term, options: [.caseInsensitive])
                    if range.location != NSNotFound {
                        found.append(ProjectTextMatch(fileURL: url, line: lineNumber, text: line))
                    }
                }
            }
        }
        return found
    }

    private static func shouldSkip(_ url: URL, language: Language?) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "gif" ||
           ext == "pdf" || ext == "zip" || ext == "app" || ext == "framework" { return true }
        // When a specific language is selected, only search files of that language.
        if let lang = language, !lang.contains(url) { return true }
        return false
    }
}
