// by cipher.org.uk
import Foundation

/// The debugger simulation (`SimDebugWindowController`): one session at a time, shared by
/// every browser tab, as the single debugger window is shared in the AppKit app.
///
/// Everything runs synchronously on the calling thread. Play runs the same single-step
/// loop as the window's timer, in one call, bounded by `playStepLimit` steps.
public final class SimDebugService {
    public static let shared = SimDebugService()

    /// The most steps one `play` call runs (the engine's own per-call limit).
    public static let playStepLimit = 2000

    // MARK: - DTOs

    /// A parameter of the simulated function, with its current seed value.
    public struct SimParameterDTO: Codable, Sendable {
        public var index: Int
        public var name: String
        public var typeHint: String
        /// The value as text, exactly as the parameter table shows it.
        public var value: String
        /// "name: value", the parameter row's summary.
        public var summary: String
        public var isBuffer: Bool
        public var capacity: Int

        public init(index: Int, name: String, typeHint: String, value: String, summary: String,
                    isBuffer: Bool, capacity: Int) {
            self.index = index
            self.name = name
            self.typeHint = typeHint
            self.value = value
            self.summary = summary
            self.isBuffer = isBuffer
            self.capacity = capacity
        }
    }

    /// A variable row of the selected stack frame.
    public struct SimWatchRowDTO: Codable, Sendable {
        public var name: String
        public var value: String
        /// True when the value changed in the last step (the window shows these in orange).
        public var changed: Bool
        public var isParameter: Bool

        public init(name: String, value: String, changed: Bool, isParameter: Bool) {
            self.name = name
            self.value = value
            self.changed = changed
            self.isParameter = isParameter
        }
    }

    /// A call-stack frame. Row order is the stack table's order.
    public struct SimFrameDTO: Codable, Sendable {
        public var index: Int
        public var functionName: String
        public var fileName: String
        public var path: String
        public var line: Int
        /// The innermost frame, where the simulation is now.
        public var isActive: Bool
        public var isDone: Bool
        /// The frame whose variables the watch table shows.
        public var isSelected: Bool

        public init(index: Int, functionName: String, fileName: String, path: String, line: Int,
                    isActive: Bool, isDone: Bool, isSelected: Bool) {
            self.index = index
            self.functionName = functionName
            self.fileName = fileName
            self.path = path
            self.line = line
            self.isActive = isActive
            self.isDone = isDone
            self.isSelected = isSelected
        }
    }

    /// A 1-based inclusive line range.
    public struct SimLineSpanDTO: Codable, Sendable {
        public var start: Int
        public var end: Int

        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }
    }

    /// Everything the debugger window shows.
    public struct SimStateDTO: Codable, Sendable {
        /// False until a function is loaded.
        public var loaded: Bool
        /// "<function> — Debugger (Experimental)".
        public var title: String
        public var functionName: String
        /// The function badge: "<name>()" of the active frame.
        public var badge: String
        public var entryPath: String
        /// The file the source pane shows; it changes when the simulation enters another file.
        public var displayedPath: String?
        /// The full text of the displayed file.
        public var sourceText: String
        /// The line being simulated, 0 before the first step.
        public var currentLine: Int
        /// The simulated function's own lines, dimmed everywhere else in its entry file. Nil when not applicable.
        public var bodyLines: SimLineSpanDTO?
        /// The status line: the effects of the last step, or "Finished.".
        public var statusText: String
        /// True once the simulation has run to the end.
        public var finished: Bool
        public var stepNumber: Int
        public var stepCount: Int
        public var parameters: [SimParameterDTO]
        public var watchRows: [SimWatchRowDTO]
        public var frames: [SimFrameDTO]
        public var selectedFrameIndex: Int
        public var canStepOver: Bool
        public var canStepInto: Bool
        public var canPlay: Bool
        public var canStepBack: Bool
        public var canReset: Bool

        public init(loaded: Bool, title: String, functionName: String, badge: String, entryPath: String,
                    displayedPath: String?, sourceText: String, currentLine: Int, bodyLines: SimLineSpanDTO?,
                    statusText: String, finished: Bool, stepNumber: Int, stepCount: Int,
                    parameters: [SimParameterDTO], watchRows: [SimWatchRowDTO], frames: [SimFrameDTO],
                    selectedFrameIndex: Int, canStepOver: Bool, canStepInto: Bool, canPlay: Bool,
                    canStepBack: Bool, canReset: Bool) {
            self.loaded = loaded
            self.title = title
            self.functionName = functionName
            self.badge = badge
            self.entryPath = entryPath
            self.displayedPath = displayedPath
            self.sourceText = sourceText
            self.currentLine = currentLine
            self.bodyLines = bodyLines
            self.statusText = statusText
            self.finished = finished
            self.stepNumber = stepNumber
            self.stepCount = stepCount
            self.parameters = parameters
            self.watchRows = watchRows
            self.frames = frames
            self.selectedFrameIndex = selectedFrameIndex
            self.canStepOver = canStepOver
            self.canStepInto = canStepInto
            self.canPlay = canPlay
            self.canStepBack = canStepBack
            self.canReset = canReset
        }
    }

    // MARK: - State (guarded by `lock`)

    private let lock = NSLock()
    private var engine: SimDebugEngine?
    private var currentSeeds: [SimParameterSeed] = []
    private var stepHistory: [SimDebugStep] = []
    private var currentStep: SimDebugStep?
    private var selectedFrameIndex = 0
    private var displayedFileURL: URL?
    private var sourceText = ""
    private var statusText = ""

    private init() {}

    // MARK: - Session

    /// Loads `function` from the file at `path` and starts a fresh simulation at its first line.
    /// The previous session is replaced only when the function is found.
    public func load(path: String, function: String) throws -> SimStateDTO {
        let name = function.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw KarmaServiceError.invalid("Choose a function to simulate.") }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KarmaServiceError.notFound("No file at \(path).")
        }
        let sourceIndex = KarmaWorkspace.shared.read { $0.sourceIndex }
        let fresh = SimDebugEngine(sourceIndex: sourceIndex, fileURL: url, functionName: name)
        guard fresh.isReady else {
            throw KarmaServiceError.notFound("No function named \(name) in \(path).")
        }

        lock.lock()
        defer { lock.unlock() }
        engine = fresh
        currentSeeds = fresh.parameters
        stepHistory = []
        currentStep = nil
        selectedFrameIndex = 0
        statusText = ""
        displayedFileURL = url
        sourceText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let initial = fresh.initialStep()
        apply(initial)
        return snapshot()
    }

    /// The current state.
    public func state() -> SimStateDTO {
        lock.lock()
        defer { lock.unlock() }
        return snapshot()
    }

    /// Runs one step: "over", "into" or "back" (the stepped-back state of the previous step).
    public func step(mode: String) throws -> SimStateDTO {
        lock.lock()
        defer { lock.unlock() }
        let session = try requireEngine()
        switch mode {
        case "over", "into":
            let stepMode: SimStepMode = mode == "into" ? .into : .over
            guard let stepped = session.stepForward(mode: stepMode) else {
                statusText = "Finished."
                return snapshot()
            }
            stepHistory.append(stepped)
            apply(stepped)
        case "back":
            guard let stepped = session.stepBack() else { return snapshot() }
            stepHistory.append(stepped)
            apply(stepped)
        default:
            throw KarmaServiceError.invalid("Unknown step mode \(mode).")
        }
        return snapshot()
    }

    /// Restores the parameter seeds and starts again at the first line.
    public func reset() -> SimStateDTO {
        lock.lock()
        defer { lock.unlock() }
        guard let session = engine else { return snapshot() }
        session.reset(withSeeds: currentSeeds)
        stepHistory = []
        apply(session.initialStep())
        return snapshot()
    }

    /// Steps over until the simulation finishes, or until `playStepLimit` steps have run.
    public func play() throws -> SimStateDTO {
        lock.lock()
        defer { lock.unlock() }
        let session = try requireEngine()
        var ran = 0
        while ran < SimDebugService.playStepLimit {
            guard let stepped = session.stepForward(mode: .over) else {
                statusText = "Finished."
                break
            }
            stepHistory.append(stepped)
            apply(stepped)
            ran += 1
        }
        return snapshot()
    }

    /// Sets parameter `index` from its text (as the seed table parses it). Takes effect at the next reset.
    public func setParameter(index: Int, text: String) throws -> SimStateDTO {
        lock.lock()
        defer { lock.unlock() }
        let session = try requireEngine()
        guard currentSeeds.indices.contains(index) else {
            throw KarmaServiceError.notFound("No parameter at index \(index).")
        }
        let seed = currentSeeds[index]
        currentSeeds[index] = SimParameterSeed(name: seed.name, typeHint: seed.typeHint,
                                               value: seed.parse(text), isBuffer: seed.isBuffer,
                                               capacity: seed.capacity)
        session.parameters = currentSeeds
        return snapshot()
    }

    /// Chooses the call-stack frame whose variables the watch table shows (`stackTable` selection).
    public func selectFrame(index: Int) throws -> SimStateDTO {
        lock.lock()
        defer { lock.unlock() }
        _ = try requireEngine()
        let frames = currentStep?.frames ?? []
        guard frames.indices.contains(index) else {
            throw KarmaServiceError.invalid("No stack frame at index \(index).")
        }
        selectedFrameIndex = index
        return snapshot()
    }

    // MARK: - Private (caller holds `lock`)

    private func requireEngine() throws -> SimDebugEngine {
        guard let session = engine else {
            throw KarmaServiceError.notFound("No debugger session is open. Load a function first.")
        }
        return session
    }

    /// Shows `step` as the current state, as `SimDebugWindowController.apply` does.
    private func apply(_ step: SimDebugStep?) {
        currentStep = step
        guard let step = step else {
            statusText = "Finished."
            return
        }
        displayStep(step)
        if let warning = step.warning, !warning.isEmpty {
            statusText = "[\(warning)] \(step.effects.joined(separator: ", "))"
        } else {
            statusText = step.effects.joined(separator: "  |  ")
        }
        selectedFrameIndex = step.activeFrameIndex
    }

    /// Switches the source pane to the active frame's file when it differs from the shown one.
    private func displayStep(_ step: SimDebugStep) {
        let activeFrame = step.frames.indices.contains(step.activeFrameIndex)
            ? step.frames[step.activeFrameIndex]
            : nil
        let activeFile = activeFrame?.fileURL ?? step.fileURL
        if displayedFileURL?.standardizedFileURL != activeFile.standardizedFileURL {
            displayedFileURL = activeFile
            sourceText = (try? String(contentsOf: activeFile, encoding: .utf8)) ?? ""
        }
    }

    private func snapshot() -> SimStateDTO {
        guard let session = engine else {
            return SimStateDTO(loaded: false, title: "Debugger (Experimental)", functionName: "", badge: "",
                               entryPath: "", displayedPath: nil, sourceText: "", currentLine: 0,
                               bodyLines: nil, statusText: statusText, finished: false, stepNumber: 0,
                               stepCount: 0, parameters: [], watchRows: [], frames: [], selectedFrameIndex: 0,
                               canStepOver: false, canStepInto: false, canPlay: false, canStepBack: false,
                               canReset: false)
        }
        let frames = currentStep?.frames ?? []
        let watchFrame: SimCallFrameView? = frames.indices.contains(selectedFrameIndex)
            ? frames[selectedFrameIndex]
            : frames.first
        let watch = (watchFrame?.variables ?? []).map {
            SimWatchRowDTO(name: $0.name, value: $0.value.display, changed: $0.changed, isParameter: $0.isParameter)
        }
        let parameters = currentSeeds.enumerated().map { index, seed in
            SimParameterDTO(index: index, name: seed.name, typeHint: seed.typeHint, value: seed.value.display,
                            summary: seed.summary, isBuffer: seed.isBuffer, capacity: seed.capacity)
        }
        let frameRows = frames.enumerated().map { index, frame in
            SimFrameDTO(index: index, functionName: frame.functionName, fileName: frame.fileName,
                        path: frame.fileURL.path, line: frame.line, isActive: frame.isActive,
                        isDone: frame.isDone, isSelected: index == selectedFrameIndex)
        }
        let activeName = currentStep.flatMap { step in
            step.frames.indices.contains(step.activeFrameIndex) ? step.frames[step.activeFrameIndex].functionName : nil
        } ?? session.functionName
        let running = currentStep != nil && !session.hasRunCompleted
        var bodyLines: SimLineSpanDTO?
        if displayedFileURL?.standardizedFileURL == session.entryFileURL,
           let range = session.functionBodyLineRange {
            bodyLines = SimLineSpanDTO(start: range.lowerBound, end: range.upperBound)
        }
        return SimStateDTO(
            loaded: true,
            title: "\(session.functionName) — Debugger (Experimental)",
            functionName: session.functionName,
            badge: "\(activeName)()",
            entryPath: session.entryFileURL.path,
            displayedPath: displayedFileURL?.path,
            sourceText: sourceText,
            currentLine: currentStep?.line ?? 0,
            bodyLines: bodyLines,
            statusText: statusText,
            finished: session.hasRunCompleted,
            stepNumber: currentStep?.index ?? 0,
            stepCount: session.steps.count,
            parameters: parameters,
            watchRows: watch,
            frames: frameRows,
            selectedFrameIndex: selectedFrameIndex,
            canStepOver: running,
            canStepInto: running,
            canPlay: running,
            canStepBack: true,
            canReset: true)
    }
}
