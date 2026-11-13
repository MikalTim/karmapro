import Foundation

/// Classifies every source line of a project with a trained Bayesian model.
/// The ML scan window and the web front end both run this.
enum BayesianProjectScanner {

    /// Result of a project scan: per-file line findings plus summary totals.
    struct ScanOutcome {
        let results: [String: [Int: Double]]
        let totalFiles: Int
        let totalLines: Int
    }

    /// Scans every matching file in the project tree, classifying each line.
    static func scanProject(root: URL, model: BayesianClassifier, extensions: Set<String>, threshold: Double = 0.80, progress: ((Int, Int) -> Void)?) -> ScanOutcome {
        let files = Self.enumerateSourceFiles(in: root, extensions: extensions)
        let total = max(files.count, 1)
        var results: [String: [Int: Double]] = [:]
        var totalLines = 0
        for (i, url) in files.enumerated() {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                var lineMap: [Int: Double] = [:]
                let lines = text.components(separatedBy: "\n")
                totalLines += lines.count
                var inBlockComment = false
                for (idx, line) in lines.enumerated() {
                    let (isComment, newInBlockComment) = Self.isCommentLine(line, inBlockComment: inBlockComment)
                    inBlockComment = newInBlockComment
                    if isComment { continue }
                    let prob = model.probabilityBad(line: line)
                    if prob >= threshold {
                        lineMap[idx + 1] = prob
                    }
                }
                if !lineMap.isEmpty {
                    results[url.path] = lineMap
                }
            }
            progress?(i + 1, total)
        }
        return ScanOutcome(results: results, totalFiles: files.count, totalLines: totalLines)
    }

    /// Returns (isComment, newInBlockCommentState). Handles // line comments and /* */ block comments.
    /// The inBlockComment parameter tracks multi-line block comment state across lines.
    static func isCommentLine(_ line: String, inBlockComment: Bool) -> (Bool, Bool) {
        var i = line.startIndex
        var inBlock = inBlockComment

        func advance(_ n: Int = 1) {
            for _ in 0..<n {
                if i < line.endIndex { i = line.index(after: i) }
            }
        }

        while i < line.endIndex {
            let c = line[i]
            if inBlock {
                if c == "*" {
                    advance()
                    if i < line.endIndex && line[i] == "/" {
                        advance()
                        inBlock = false
                    }
                } else {
                    advance()
                }
            } else {
                if c == "/" {
                    advance()
                    if i < line.endIndex {
                        let next = line[i]
                        if next == "/" {
                            return (true, inBlock) // rest of line is comment
                        } else if next == "*" {
                            advance()
                            inBlock = true
                        }
                    }
                } else if c == " " || c == "\t" {
                    advance()
                } else {
                    // Non-whitespace code encountered
                    break
                }
            }
        }

        // Line is a comment if we're still in a block comment (and didn't exit) OR
        // if we only saw comment tokens and whitespace.
        let onlyComment = inBlock || (i >= line.endIndex)
        return (onlyComment, inBlock)
    }

    static func enumerateSourceFiles(in root: URL, extensions: Set<String>) -> [URL] {
        if extensions.isEmpty { return SourceTree.enumerateAll(in: root) }
        return SourceTree.enumerate(extensions: extensions, in: root)
    }
}
