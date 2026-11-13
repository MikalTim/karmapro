import Foundation

/// The AI triage pass over security-scan findings: the system prompt, the
/// per-finding prompt, the verdict parser and the retry classifier. The scan
/// window and the web scan service both use these, so the two front ends send
/// the same question and read the same answer.
enum ScanTriage {
    /// System prompt sent with every triage request.
    static let systemPrompt = """
    You are a security triage researcher. You are shown a finding reported by a static analysis scanner, including the code around the reported line. Decide whether it is a genuine, exploitable security issue or a false positive / non-issue / purely informational. Answer with exactly one word: VALID or INVALID.
    """

    /// True when a failed triage request may succeed on a retry (rate limit,
    /// upstream 5xx, dropped/timed-out connection). A bad key or model is not.
    static func isTransientFailure(_ error: Error) -> Bool {
        let lower = error.localizedDescription.lowercased()
        if lower.contains("credit") || lower.contains("insufficient") || lower.contains("balance")
            || lower.contains("402") || lower.contains("unauthorized") || lower.contains("401")
            || lower.contains("not found") || lower.contains("no api key") {
            return false
        }
        if lower.contains("429") || lower.contains("rate limit") || lower.contains("too many")
            || lower.contains("quota") {
            return true
        }
        return lower.contains("500") || lower.contains("502") || lower.contains("503")
            || lower.contains("504") || lower.contains("timeout") || lower.contains("timed out")
            || lower.contains("connection") || lower.contains("network")
            || lower.contains("empty response") || lower.contains("overloaded")
            || lower.contains("temporarily") || lower.contains("unavailable")
    }

    /// User prompt for one finding: its metadata followed by the code around it.
    static func prompt(for f: ScanFinding) -> String {
        var parts: [String] = []
        parts.append("Category: \(f.category)")
        parts.append("Severity: \(f.severity.label)")
        parts.append("Message: \(f.message)")
        if let p = f.taintPath, !p.isEmpty { parts.append("Data flow: \(p)") }
        parts.append("Function: \(f.function)")
        parts.append("File: \(f.fileURL.path)")
        parts.append("Line: \(f.line)")
        if let snippet = codeSnippet(for: f) {
            parts.append("Code around the line:\n\(snippet)")
        }
        parts.append("Answer with VALID or INVALID only.")
        return parts.joined(separator: "\n")
    }

    /// Lines around the finding, capped, so the model judges real code.
    static func codeSnippet(for f: ScanFinding) -> String? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: f.fileURL.path),
              let size = attrs[.size] as? Int, size < 1_000_000 else { return nil }
        guard let text = try? String(contentsOf: f.fileURL, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")
        let start = max(0, f.line - 21)
        let end = min(lines.count, f.line + 25)
        guard start < end else { return nil }
        return (start..<end).map { i in
            let marker = (i + 1) == f.line ? ">>>" : "   "
            return "\(marker) \(i + 1)| \(lines[i])"
        }.joined(separator: "\n")
    }

    /// Reads a model answer: INVALID wins over VALID; anything else is nil.
    static func parseVerdict(_ raw: String) -> Bool? {
        let t = raw.uppercased()
        if t.contains("INVALID") { return false }
        if t.contains("VALID") { return true }
        return nil
    }
}
