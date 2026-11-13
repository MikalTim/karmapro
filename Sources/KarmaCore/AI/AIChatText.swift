import Foundation

/// Pure text helpers for the AI chat: streamed-markdown splitting, tool-call
/// display strings and the system prompt. Shared by the AppKit window and the
/// web service. No UI types.
enum AIChatText {

    /// Splits streamed markdown into the part that has settled and the block
    /// still being written. A block ends at a blank line, but only outside a
    /// fenced code block: an unclosed fence still changes how everything after
    /// it is styled, so nothing behind one is treated as settled.
    static func splitSettledStream(_ text: String) -> (settled: String, live: String) {
        guard !text.isEmpty else { return ("", "") }
        let lines = text.components(separatedBy: "\n")
        // Count fences the way `attributedMarkdownResponse` does, so both
        // halves style identically when rendered apart.
        var fenceCount = 0
        var boundary = -1
        for (index, line) in lines.enumerated() {
            fenceCount += line.components(separatedBy: "```").count - 1
            if fenceCount % 2 == 0, line.trimmingCharacters(in: .whitespaces).isEmpty {
                boundary = index
            }
        }
        guard boundary >= 0 else { return ("", text) }
        var settled = lines[0...boundary].joined(separator: "\n")
        if boundary + 1 < lines.count { settled += "\n" }
        let live = boundary + 1 < lines.count
            ? lines[(boundary + 1)...].joined(separator: "\n")
            : ""
        return (settled, live)
    }

    /// Terminal-friendly tool label: "$ name (key: value, …)" instead of raw
    /// JSON arguments.
    static func toolDisplayLabel(name: String, args: String) -> String {
        if let data = args.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           !obj.isEmpty {
            let pairs = obj.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            return "$ \(name)(\(pairs))"
        }
        return "$ \(name)"
    }

    /// Terminal-friendly tool result: human-readable summary instead of the
    /// raw JSON envelope.
    static func toolDisplayOutput(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(raw.prefix(300))
        }
        if let error = obj["error"] as? String { return "error: \(error)" }
        if let output = obj["output"] as? String {           // run_command output
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let single = trimmed.replacingOccurrences(of: "\n", with: " ⏎ ")
            return single.isEmpty ? "(no output)" : String(single.prefix(300))
        }
        if let entries = obj["entries"] as? [String] {        // list_files
            let head = entries.prefix(12).joined(separator: ", ")
            return entries.isEmpty ? "(empty)" :
                "\(entries.count) entries: \(head)\(entries.count > 12 ? ", …" : "")"
        }
        if let matches = obj["matches"] as? [String] {        // search_files
            return matches.isEmpty ? "no matches" : "\(matches.count) matches"
        }
        if let content = obj["content"] as? String {          // read_file
            return "read \(content.count) chars"
        }
        if (obj["ok"] as? Bool) == true { return "ok" }
        return String(raw.prefix(300))
    }

    /// The system message sent with every request; anchors the model to the
    /// project currently open in Karma Pro and explains the sandboxed tools.
    static func systemPrompt(projectRoot: URL?) -> String {
        var parts = ["You are a senior software analysis assistant embedded in Karma Pro, a static-analysis IDE."]
        if let root = projectRoot {
            parts.append("The user's project directory is: \(root.path)")
            parts.append("File paths in the conversation are relative to that directory.")
        }
        parts.append("You have tools to inspect the project: list_files, read_file, search_files, and run_command (read-only commands executed inside the project directory). Use them to analyse the actual source code before answering instead of guessing. All tools are strictly confined to the project directory: never read, list, search, or run anything outside it, and never attempt to modify or delete files. Prefer search_files/read_file over shell commands. Cite concrete file paths and line numbers in your answers.")
        return parts.joined(separator: " ")
    }
}
