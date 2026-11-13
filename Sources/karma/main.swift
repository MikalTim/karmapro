// by cipher.org.uk
//
// Headless front end for the Karma Pro scanning engine. Prints one JSON
// document (see `ScanReport`) and nothing else on stdout, so the output can be
// piped straight into jq or another tool.
import Foundation
import KarmaCore
#if WebServer
import KarmaServer
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

let usage = """
Usage:
  karma [scan] <path> [options]   Statically scan a project; print a JSON report.
  karma --serve [--host <addr>] [--port <n>]   Start the web front end (default http://127.0.0.1:8790/).
  karma --help

Scan options:
  --min-severity <level>   Only report findings at or above: low, medium, high, critical (default: low).
  --output <file>          Write the JSON report to <file> instead of stdout.
  --compact                Single-line JSON instead of pretty-printed.
  --progress               Report per-file progress on stderr.
  --verbose                Forward the engine's diagnostic log to stderr.

Exit status: 0 scan completed, 1 scan failed, 2 usage error.
"""

struct Options {
    var root: String?
    var minimumSeverity: ScanReport.Severity = .low
    var output: String?
    var pretty = true
    var progress = false
    var verbose = false
}

enum Command {
    case scan(Options)
    case serve(host: String, port: Int)
    case help
}

struct UsageError: Error {
    let message: String
}

func parse(_ arguments: [String]) throws -> Command {
    var options = Options()
    var serve = false
    var host: String?
    var port: Int?
    var args = arguments[...]
    if args.first == "scan" { args = args.dropFirst() }
    while let arg = args.popFirst() {
        switch arg {
        case "-h", "--help":
            return .help
        case "--serve":
            serve = true
        case "--host":
            guard let value = args.popFirst() else { throw UsageError(message: "--host needs an address") }
            host = value
        case "--port":
            guard let value = args.popFirst() else { throw UsageError(message: "--port needs a number") }
            guard let number = Int(value), (1...65535).contains(number) else {
                throw UsageError(message: "invalid port '\(value)' (expected 1 to 65535)")
            }
            port = number
        case "--min-severity":
            guard let value = args.popFirst() else { throw UsageError(message: "--min-severity needs a value") }
            guard let level = ScanReport.Severity(rawValue: value.lowercased()) else {
                throw UsageError(message: "unknown severity '\(value)' (expected low, medium, high or critical)")
            }
            options.minimumSeverity = level
        case "-o", "--output":
            guard let value = args.popFirst() else { throw UsageError(message: "\(arg) needs a file path") }
            options.output = value
        case "--compact":
            options.pretty = false
        case "--progress":
            options.progress = true
        case "-v", "--verbose":
            options.verbose = true
        default:
            if arg.hasPrefix("-") { throw UsageError(message: "unknown option '\(arg)'") }
            guard options.root == nil else { throw UsageError(message: "only one project path may be given") }
            options.root = arg
        }
    }
    if serve {
        guard options.root == nil else { throw UsageError(message: "--serve does not take a project path") }
        return .serve(host: host ?? "127.0.0.1", port: port ?? 8790)
    }
    if host != nil || port != nil { throw UsageError(message: "--host and --port only apply to --serve") }
    guard options.root != nil else { throw UsageError(message: "missing project path") }
    return .scan(options)
}

func writeStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// The engine logs progress with `print`. Point stdout at stderr (verbose) or
/// /dev/null for the duration of the run and return a descriptor for the
/// original stdout, so the JSON report is the only thing written there.
func captureStdout(verbose: Bool) -> Int32 {
    fflush(stdout)
    let original = dup(STDOUT_FILENO)
    let sink = verbose ? STDERR_FILENO : open("/dev/null", O_WRONLY)
    dup2(sink, STDOUT_FILENO)
    if sink != STDERR_FILENO { close(sink) }
    return original
}

func runScan(_ options: Options) -> Int32 {
    let root = URL(fileURLWithPath: options.root!)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        writeStderr("karma: '\(root.path)' is not a directory")
        return 1
    }

    let reportFD = captureStdout(verbose: options.verbose)
    let progress: ((Int, Int) -> Void)? = options.progress ? { done, total in
        writeStderr("karma: scanning \(done + 1)/\(total)")
    } : nil
    let report = KarmaScanner.scan(root: root, progress: progress)
        .filtered(minimumSeverity: options.minimumSeverity)
    fflush(stdout)

    let data: Data
    do {
        data = try report.jsonData(pretty: options.pretty) + Data("\n".utf8)
    } catch {
        writeStderr("karma: could not encode the report: \(error)")
        return 1
    }
    if let output = options.output {
        do {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        } catch {
            writeStderr("karma: could not write '\(output)': \(error.localizedDescription)")
            return 1
        }
    } else {
        FileHandle(fileDescriptor: reportFD, closeOnDealloc: false).write(data)
    }
    return 0
}

/// Points the engine at its bundled resources (prompts, models, Info.plist).
/// First hit wins: `KARMA_RESOURCES`, `karma-resources` next to the binary,
/// then `Resources_src` in the source tree this binary was built from. A
/// candidate must contain `Info.plist`.
func configureResources() {
    var candidates: [URL] = []
    if let env = ProcessInfo.processInfo.environment["KARMA_RESOURCES"], !env.isEmpty {
        candidates.append(URL(fileURLWithPath: env, isDirectory: true))
    }
    if let executableDirectory = KarmaResources.executableDirectory {
        candidates.append(executableDirectory.appendingPathComponent("karma-resources", isDirectory: true))
    }
    // <repo>/Sources/karma/main.swift → <repo>
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    candidates.append(repo.appendingPathComponent("Resources_src", isDirectory: true))
    KarmaResources.directory = candidates.first {
        FileManager.default.fileExists(atPath: $0.appendingPathComponent("Info.plist").path)
    }
}

func runServe(host: String, port: Int) async -> Int32 {
    #if WebServer
    return await KarmaWebServer.run(host: host, port: port)
    #else
    writeStderr("karma: --serve is not available: this karma was built without the WebServer trait (rebuild without --disable-default-traits).")
    return 2
    #endif
}

configureResources()
let status: Int32
do {
    switch try parse(Array(CommandLine.arguments.dropFirst())) {
    case .help:
        print(usage)
        status = 0
    case .serve(let host, let port):
        status = await runServe(host: host, port: port)
    case .scan(let options):
        status = runScan(options)
    }
} catch let error as UsageError {
    writeStderr("karma: \(error.message)\n\n\(usage)")
    status = 2
} catch {
    writeStderr("karma: \(error)")
    status = 2
}
exit(status)
