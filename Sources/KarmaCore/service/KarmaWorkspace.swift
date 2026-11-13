// by cipher.org.uk
import Foundation

/// What a front end shows about the open project.
public struct ProjectInfoDTO: Codable, Sendable {
    /// Absolute path of the project folder, or nil when none is open.
    public var root: String?
    /// The folder's name (what the title shows before " Project").
    public var name: String?
    /// The index build job for this project, if one was started.
    public var indexJobId: String?
    /// "none", "building", "ready", "cancelled" or "failed".
    public var indexState: String
    /// True while a pull request review is open.
    public var reviewing: Bool
}

/// The state `MainWindowController` keeps in properties: the one open project,
/// its parsed source index and the caches derived from it. The server has one
/// workspace, so every browser tab sees the same project.
public final class KarmaWorkspace: @unchecked Sendable {
    public static let shared = KarmaWorkspace()

    struct State {
        var root: URL?
        /// The whole file tree, read once when the project opens (`FileNode.loadDeeply`).
        var rootNode: FileNode?
        var sourceIndex: ProjectSourceIndex?
        var definitionIndex: DefinitionIndex?
        var tracer: VariableFlowTracer?
        var callGraph: ProjectCallGraph?
        var indexJobID: String?
        var indexState = "none"
        /// Bumped on every open or close, so a stale index build never publishes into a newer project.
        var generation = 0
        /// The pull request review being shown, if any.
        var reviewSession: PRReviewSession?
        /// Repo-relative paths the open pull request changes; nil outside a review.
        var prChangedPaths: Set<String>?
        /// File name → "A" or "M" for the review's changed files.
        var changeBadges: [String: String] = [:]
        /// The user asked to see the whole project instead of just the changed files.
        var showAllFiles = false
    }

    private let lock = NSLock()
    private var state = State()
    private let jobs: KarmaJobCenter
    private let bus: KarmaEventBus

    public init(jobs: KarmaJobCenter = .shared, bus: KarmaEventBus = .shared) {
        self.jobs = jobs
        self.bus = bus
    }

    // MARK: - State access for the services

    func read<T>(_ body: (State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(state)
    }

    func modify<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }

    /// The open project's folder, or `KarmaServiceError.noProject`.
    func requireRoot() throws -> URL {
        guard let root = read({ $0.root }) else { throw KarmaServiceError.noProject }
        return root
    }

    public var rootPath: String? {
        read { $0.root?.path }
    }

    public func info() -> ProjectInfoDTO {
        read { state in
            ProjectInfoDTO(root: state.root?.path,
                           name: state.root?.lastPathComponent,
                           indexJobId: state.indexJobID,
                           indexState: state.indexState,
                           reviewing: state.reviewSession != nil)
        }
    }

    // MARK: - Opening a project

    /// Opens `path` as the project (`MainWindowController.promptForDirectory`):
    /// reads the file tree, drops every cache from the previous project and
    /// starts the index build. Returns the id of the index job.
    @discardableResult
    public func open(root path: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw KarmaServiceError.notADirectory(path)
        }
        let node = FileNode(url: url, isDirectory: true)
        node.loadDeeply()

        let (generation, previousJob) = modify { state -> (Int, String?) in
            let previous = state.indexJobID
            state = State(root: url, rootNode: node, indexState: "building", generation: state.generation + 1)
            return (state.generation, previous)
        }
        if let previousJob { jobs.cancel(previousJob) }

        let id = jobs.start(kind: "index") { [self] context in
            let cancellation = context.cancellationToken()
            let index = ProjectSourceIndex(projectRoot: url, cancellation: cancellation) { done, total in
                context.progress(done: done, total: total, stage: "Indexing \(done) of \(total) files")
            }
            guard !index.wasCancelled, !cancellation.isCancelled else {
                finishIndex(generation: generation, state: "cancelled")
                return nil
            }
            // Derive the viewer indexes in memory (no further I/O or parsing).
            let definitionIndex = DefinitionIndex.build(sourceIndex: index)
            let tracer = VariableFlowTracer(sourceIndex: index)
            // Pre-build the call graph so the first Focus or reachability request resolves from the cache.
            let callGraph = ProjectCallGraph(sourceIndex: index)
            modify { state in
                guard state.generation == generation else { return }
                state.sourceIndex = index
                state.definitionIndex = definitionIndex
                state.tracer = tracer
                state.callGraph = callGraph
                state.indexState = "ready"
            }
            return nil
        }
        modify { state in
            if state.generation == generation { state.indexJobID = id }
        }
        bus.post("workspace.changed", WorkspaceChangedEvent(root: url.path, name: url.lastPathComponent))
        return id
    }

    private func finishIndex(generation: Int, state newState: String) {
        modify { state in
            if state.generation == generation { state.indexState = newState }
        }
    }

    /// Closes the project and drops everything derived from it
    /// (`FileTreeViewController.clear` plus the cache resets).
    public func close() {
        let previousJob = modify { state -> String? in
            let previous = state.indexJobID
            state = State(generation: state.generation + 1)
            return previous
        }
        if let previousJob { jobs.cancel(previousJob) }
        bus.post("workspace.changed", WorkspaceChangedEvent(root: nil, name: nil))
    }
}
