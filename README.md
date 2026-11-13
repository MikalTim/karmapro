# Karma Pro: The Code Security Review tool
<img width="619" height="426" alt="image" src="https://github.com/user-attachments/assets/709007a8-c63f-4d99-adaa-0d7dd3ef4949" />

Karma Pro is an open source code review tool (written in Swift) that can assist code reviewers with a multitude of useful tools. Karma Pro is a macOS source-code security scanner (AST base and Heuristics) that statically analyses projects in multiple languages. It's backed by an ML classifier trained on real patches to catch subtle issues ([Karma Automated source code defect identification method
](https://cipher.org.uk/2026/02/08/Karma-Automated-source-code-defect-identification-method/)). Beyond scanning, it offers interactive call graphs and data-flow diagrams, debugger (a lightweight dynamic simulator experimental), a bug tracker, a private research wiki, notes, backups, and an AI assistant.

#### Pull Request Monitoring & Review Scanning (optional)
The Karma Pro menu bar icon can watch repositories on GitHub, GitLab, Bitbucket and Gitea/Forgejo, tell you when a pull request opens or changes, and check that pull request and scan it. Monitoring is off by default.
<img width="619" height="435" alt="image" src="https://github.com/user-attachments/assets/4db3329e-b995-4556-96bb-40be275650de" />
<img width="619" height="279" alt="image" src="https://github.com/user-attachments/assets/b61dbdbe-16c5-4d1b-93c8-a36b10fa4abd" />

To build Karma Pro download the repo and build it with `./build.sh` (at least Xcode 14+ / Swift 5.7). Download the self-signed release [here](https://github.com/cphr/karmapro/releases/latest/download/Karma.pro.dmg)

#### Source layout and front ends
| Path | What | Platforms |
|---|---|---|
| `Sources/KarmaCore` | Scanning engine (parsers, analyzers, detectors, indexes, stores). Foundation only; the public entry point is `KarmaScanner.scan(root:)` → Codable `ScanReport`. | macOS, Linux |
| `Sources/karma` | Headless CLI: scans a directory and prints a JSON report. | macOS, Linux |
| `Sources/KarmaAppKit` | The AppKit desktop app, plus macOS-only services (Keychain, CryptoKit backups, `Network` MCP server, RTF wiki store). | macOS |

Build options:
- `./build.sh` (macOS) builds `Karma Pro.app` from `KarmaCore` + `KarmaAppKit`.
- `./build.sh --no-appkit` (any OS; the default on Linux) builds only the CLI, via SwiftPM (Swift 5.9+).
- `swift build` / `swift test` build and test `KarmaCore` and the CLI; SwiftPM never compiles the AppKit sources.

#### CLI usage
The headless `karma` CLI runs the built-in static scan (AST + heuristic engines) over a directory and prints a JSON report. Stdout carries only the JSON document, so it can be piped straight into `jq` or another tool; progress and diagnostics go to stderr.

```
karma [scan] <path> [options]   Statically scan a project; print a JSON report.
karma --serve                   Start the web front end (not included in this build).
karma --help
```

| Option | Effect |
|---|---|
| `--min-severity <level>` | Only report findings at or above `low`, `medium`, `high` or `critical` (default: `low`). |
| `-o`, `--output <file>` | Write the report to `<file>` instead of stdout. |
| `--compact` | Single-line JSON instead of pretty-printed. |
| `--progress` | Report per-file progress on stderr. |
| `-v`, `--verbose` | Forward the engine's diagnostic log to stderr. |

Exit status: `0` scan completed, `1` scan failed (e.g. the path is not a directory), `2` usage error. A completed scan exits `0` whether or not it found anything. `--serve` is reserved for the upcoming web front end and is rejected by this build.

Examples:
```sh
# Build, then scan a project
./build.sh --no-appkit
karma=$(swift build -c release --show-bin-path)/karma
$karma ~/src/myproject > report.json

# High and critical findings only, as file:line category
$karma ~/src/myproject --min-severity high | jq -r '.findings[] | "\(.file):\(.line) \(.category)"'

# Severity counts
$karma ~/src/myproject --compact | jq .summary.bySeverity
```

Report format (abridged):
```json
{
  "cancelled" : false,
  "durationSeconds" : 0.0069,
  "filesScanned" : 1,
  "findings" : [
    {
      "category" : "Format String",
      "crossFile" : false,
      "engine" : "AST",
      "exploitability" : "medium",
      "file" : "vuln.c",
      "function" : "main",
      "line" : 3,
      "message" : "Non-constant printf format string.",
      "reachable" : true,
      "severity" : "medium"
    }
  ],
  "root" : "/tmp/demo",
  "startedAt" : "2026-11-13T12:08:27Z",
  "summary" : {
    "byCategory" : { "Format String" : 1 },
    "byEngine" : { "AST" : 1 },
    "bySeverity" : { "critical" : 0, "high" : 0, "low" : 0, "medium" : 1 },
    "total" : 1
  }
}
```

Each finding has these fields:
- `file`: path relative to the scanned root.
- `line`: 1-based.
- `function`: the enclosing function, or empty for file-level findings.
- `severity` and `exploitability`: `critical` / `high` / `medium` / `low`.
- `engine`: `AST` or `Heuristic`.
- `reachable`: whether the enclosing function is reachable at runtime.
- `crossFile`: true when the tainted data comes from another file.
- `taint` and `taintPath`: the data-flow trace, when there is one.
- `package`: `name@version`, for package findings.

Fields with no value are left out. Findings are ordered most severe first, then by file, line and category, so the same project always produces the same report.

Karma Pro post at [Cipher](https://www.cipher.org.uk) here [https://cipher.org.uk/2026/09/19/Karma-Pro-The-Code-Security-Review-tool/](https://cipher.org.uk/2026/09/19/Karma-Pro-The-Code-Security-Review-tool/)

[ReviewCode.org](https://ReviewCode.org) is Karma Pro's dedicated website about the latest updates.
