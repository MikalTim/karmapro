import Foundation

/// Graph search used by the reachability diagram.
enum ReachabilityPaths {
    /// BFS shortest path (fewest hops, deterministic tie-break by insertion
    /// order) from any `sources` node to `target` using `edges` as a directed
    /// caller→callee chain. Returns nil when no path exists.
    static func shortestPath(from sources: Set<String>, to target: String,
                             in edges: [(String, String)]) -> [String]? {
        guard !sources.isEmpty else { return nil }
        var parents: [String: String] = [:]
        var visited = sources
        var frontier = Array(sources).sorted()
        while !frontier.isEmpty {
            var next: [String] = []
            for node in frontier {
                if node == target {
                    var path = [node]
                    var cur = node
                    while let p = parents[cur] {
                        path.insert(p, at: 0)
                        cur = p
                    }
                    return path
                }
                for (from, to) in edges where from == node && !visited.contains(to) {
                    visited.insert(to)
                    parents[to] = node
                    next.append(to)
                }
            }
            frontier = next.sorted()
        }
        return nil
    }
}
