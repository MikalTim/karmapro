// by cipher.org.uk
import Foundation

extension FileNode {
    /// Returns a pruned copy keeping only files that belong to `language`.
    /// Directories are kept only when they still contain a matching file.
    func filtered(language: Language) -> FileNode {
        filtered { language.contains($0.url) }
    }

    /// Returns a pruned copy keeping only files accepted by `keep`.
    /// Directories are kept only when they still contain an accepted file.
    /// `keep` is never called with a directory.
    func filtered(_ keep: (FileNode) -> Bool) -> FileNode {
        guard isDirectory else {
            return keep(self) ? self : FileNode.prunedCopy(of: self)
        }
        let copy = FileNode.prunedCopy(of: self)
        for child in children {
            if child.isDirectory {
                let sub = child.filtered(keep)
                if !sub.children.isEmpty {
                    copy.children.append(sub)
                }
            } else if keep(child) {
                copy.children.append(child)
            }
        }
        return copy
    }

    /// Every descendant whose name contains `query`, depth first. The node itself
    /// is not included. `query` must already be trimmed and lowercased.
    func matchingFiles(query: String) -> [FileNode] {
        var matches: [FileNode] = []
        collectMatches(into: &matches, query: query)
        return matches
    }

    private func collectMatches(into matches: inout [FileNode], query: String) {
        for child in children {
            if child.name.lowercased().contains(query) {
                matches.append(child)
            }
            if child.isDirectory {
                child.collectMatches(into: &matches, query: query)
            }
        }
    }

    /// True when a node is inside the set of paths a pull request changed.
    ///
    /// Matched on the path relative to the project `root`, because the diff is
    /// reported repo-relative while the tree holds absolute URLs.
    static func matchesPullRequest(_ node: FileNode, paths: Set<String>, root: URL) -> Bool {
        let base = root.standardizedFileURL.path
        let full = node.url.standardizedFileURL.path
        var relative = full
        if full.hasPrefix(base) {
            relative = String(full.dropFirst(base.count))
        }
        while relative.hasPrefix("/") { relative.removeFirst() }

        if node.isDirectory {
            // Keep a directory when any changed path sits beneath it.
            let prefix = relative.isEmpty ? "" : relative + "/"
            return paths.contains { $0 == relative || $0.hasPrefix(prefix) }
        }
        return paths.contains(relative)
    }
}
