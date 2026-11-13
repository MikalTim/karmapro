import Foundation

/// One `new <ClassName>(` site found by `ClassUsageScanner`.
struct ClassUsageOccurrence {
    let fileURL: URL
    let line: Int
    let snippet: String
}

/// Finds Java and C# instantiations of a class (`new ClassName(...)`) across a project.
enum ClassUsageScanner {
    /// Finds all `new <className>(` occurrences in `.java`/`.cs` files under `root`.
    static func scanInstantiations(of className: String, in root: URL) -> [ClassUsageOccurrence] {
        var hits: [ClassUsageOccurrence] = []
        for url in SourceTree.enumerate(extensions: ["java", "cs", "csx"], in: root) {
            // Keep the window's own test-directory exclusion on top of the
            // shared walker's build/vendor/node_modules/.git skip list.
            if url.path.contains("/test/") { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            hits.append(contentsOf: findOccurrences(of: className, in: text, inFile: url))
        }
        return hits
    }

    /// Locates `new <className>(`/`new <className><Type>(` matches with their line + snippet.
    static func findOccurrences(of className: String, in text: String, inFile url: URL) -> [ClassUsageOccurrence] {
        var out: [ClassUsageOccurrence] = []
        let ns = text as NSString
        let pattern = "new\\s+\(NSRegularExpression.escapedPattern(for: className))(?:\\s*<[^;]*?>)?\\s*\\("
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }

        regex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match else { return }
            let r = match.range
            // Compute the 1-based line number of the match start.
            let prefix = ns.substring(with: NSRange(location: 0, length: r.location))
            let line = prefix.reduce(0) { $1 == "\n" ? $0 + 1 : $0 } + 1
            // A short snippet around the instantiation.
            let snippetLoc = max(0, r.location)
            let snippetLen = min(ns.length - snippetLoc, 80)
            let snippet = ns.substring(with: NSRange(location: snippetLoc, length: snippetLen))
            out.append(ClassUsageOccurrence(fileURL: url, line: line, snippet: snippet))
        }
        return out
    }
}
