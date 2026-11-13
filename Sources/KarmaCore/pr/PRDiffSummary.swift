import Foundation

/// One-line summary of a changed file for the PR diff view: added and removed
/// counts, the previous path for renames, and how many added lines the
/// heuristic wants read closely.
enum PRDiffSummary {
    static func summary(for file: ChangedFile) -> String {
        let added = file.addedLines.count
        let removed = file.removedLines.count
        let old = file.oldPath.map { " (was \($0))" } ?? ""
        let risky = SuspiciousLine.flagged(file).count
        let flagged = risky == 0 ? ""
            : "  \u{2022}  \(risky) line(s) worth reading closely"
        return "+\(added)  \u{2212}\(removed)\(old)\(flagged)"
    }
}

/// A deliberately small, deliberately explainable heuristic.
///
/// The scanner's real analysis is the classification pass over the project's
/// code; this exists so that the diff view can point at the lines a reviewer
/// should read first. It flags by content, and every flag says why, so it never
/// claims to be a verdict.
enum SuspiciousLine {
    private static let patterns: [(String, String)] = [
        ("exec(", "runs a command"),
        ("eval(", "evaluates code"),
        ("system(", "runs a shell command"),
        ("Runtime.getRuntime()", "reflective access"),
        ("Process(", "spawns a process"),
        ("subprocess", "spawns a process"),
        ("os.system", "runs a shell command"),
        ("shell=True", "runs a shell command"),
        ("popen(", "runs a shell command"),
        ("SELECT ", "database query"),
        ("INSERT ", "database write"),
        ("UPDATE ", "database write"),
        ("DELETE ", "database delete"),
        ("query(", "database query"),
        ("raw(", "unparameterised query"),
        ("execute(", "database call"),
        ("password", "credential handling"),
        ("secret", "credential handling"),
        ("apiKey", "credential handling"),
        ("api_key", "credential handling"),
        ("token", "credential handling"),
        ("privateKey", "credential handling"),
        ("chmod 777", "world-writable permissions"),
        ("setTimeout(", "timing behaviour"),
        ("sleep(", "timing behaviour"),
        ("|", "shell pipe"),
        ("&&", "command chaining"),
        ("http://", "unencrypted transport"),
        ("verify=False", "TLS verification disabled"),
        ("verify_mode = 0", "TLS verification disabled"),
        ("SSRF", "network access"),
        ("deserialize", "deserialisation"),
        ("pickle.loads", "deserialisation"),
        ("yaml.load", "deserialisation"),
        ("eval(", "evaluates code")
    ]

    /// True when the line contains something a reviewer should confirm. Returns
    /// false for ordinary code; the check is on the text, so comments quoting a
    /// pattern will match, and that is deliberate -- it stays on the safe side.
    static func isSuspicious(_ line: String) -> Bool {
        for (pattern, _) in patterns where line.contains(pattern) { return true }
        return false
    }

    static func flagged(_ file: ChangedFile) -> [String] {
        file.addedLines.filter { isSuspicious($0) }
    }
}
