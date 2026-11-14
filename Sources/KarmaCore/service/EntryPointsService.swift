// by cipher.org.uk
import Foundation

/// The entry-point finder (`EntryPointsWindowController`): project-wide search for
/// external inputs, the optional indirect tier, and the variable-flow trace of a
/// selected entry. One result set at a time, shared by every browser tab.
///
/// Work runs as jobs. A newer request supersedes the older job's results (they are
/// discarded), as the window cancels its previous work when a new one starts.
public final class EntryPointsService {
    public static let shared = EntryPointsService()

    /// Window title, without the busy suffix.
    public static let titleText = "Find external entries to the application"

    // MARK: - DTOs

    /// One receive call or property read.
    public struct EntrySiteDTO: Codable, Sendable {
        /// `"<path>#<charIndex>"`; pass it to `trace(siteID:)`.
        public var id: String
        public var path: String
        /// The path relative to the project root (the file name outside it).
        public var relativePath: String
        public var line: Int
        public var column: Int
        /// Matched API leaf name, for example `recv`.
        public var apiName: String
        /// The receiver path, for example `request.getParameter`.
        public var apiPath: String
        public var category: String
        /// "internet" or "local".
        public var origin: String
        /// "primary" or "indirect".
        public var confidence: String
        /// The variable the value is stored in, or nil when it is consumed inline (nothing to trace).
        public var entryVariable: String?
        public var snippet: String
        /// The snippet to show: the source line, or "→ <apiPath>" when the line is empty.
        public var displaySnippet: String
        /// The row label: "<relative path>:<line>".
        public var label: String
        /// How the site was recognised ("API call", "HTTP handler", ...).
        public var sourceKind: String

        public init(id: String, path: String, relativePath: String, line: Int, column: Int, apiName: String,
                    apiPath: String, category: String, origin: String, confidence: String,
                    entryVariable: String?, snippet: String, displaySnippet: String, label: String,
                    sourceKind: String) {
            self.id = id
            self.path = path
            self.relativePath = relativePath
            self.line = line
            self.column = column
            self.apiName = apiName
            self.apiPath = apiPath
            self.category = category
            self.origin = origin
            self.confidence = confidence
            self.entryVariable = entryVariable
            self.snippet = snippet
            self.displaySnippet = displaySnippet
            self.label = label
            self.sourceKind = sourceKind
        }
    }

    /// A category of entries, with its sites.
    public struct EntryGroupDTO: Codable, Sendable {
        public var id: String
        public var category: String
        /// "internet" or "local".
        public var origin: String
        /// "primary" or "indirect".
        public var confidence: String
        /// The badge after the category: "◉ remote", "◈ local" or "~ indirect".
        public var badge: String
        /// The group's header: "<category> — N site(s)".
        public var title: String
        public var sites: [EntrySiteDTO]

        public init(id: String, category: String, origin: String, confidence: String, badge: String,
                    title: String, sites: [EntrySiteDTO]) {
            self.id = id
            self.category = category
            self.origin = origin
            self.confidence = confidence
            self.badge = badge
            self.title = title
            self.sites = sites
        }
    }

    /// A box of the flow diagram.
    public struct EntryTraceNodeDTO: Codable, Sendable {
        public var name: String
        /// The file and line to open when clicked; nil for the Remote/Local origin box.
        public var path: String?
        public var line: Int?
        public var isStart: Bool
        public var isOrigin: Bool

        public init(name: String, path: String?, line: Int?, isStart: Bool, isOrigin: Bool) {
            self.name = name
            self.path = path
            self.line = line
            self.isStart = isStart
            self.isOrigin = isOrigin
        }
    }

    /// A data-flow arrow between two boxes, by name.
    public struct EntryTraceEdgeDTO: Codable, Equatable, Sendable {
        public var from: String
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// The flow of one selected entry.
    public struct EntryTraceDTO: Codable, Sendable {
        public var siteID: String
        /// The diagram caption.
        public var caption: String
        /// "Remote" or "Local".
        public var originLabel: String
        public var nodes: [EntryTraceNodeDTO]
        public var edges: [EntryTraceEdgeDTO]

        public init(siteID: String, caption: String, originLabel: String, nodes: [EntryTraceNodeDTO],
                    edges: [EntryTraceEdgeDTO]) {
            self.siteID = siteID
            self.caption = caption
            self.originLabel = originLabel
            self.nodes = nodes
            self.edges = edges
        }
    }

    /// Everything the entry-point window shows.
    public struct EntryPointsStateDTO: Codable, Sendable {
        /// The window title, with " — searching…" while busy.
        public var title: String
        public var busy: Bool
        /// The progress line while busy, for example "Finding entry points…" or "3 of 10 source files".
        public var progressText: String
        public var progressDone: Int
        public var progressTotal: Int
        /// The "Include indirect entries" checkbox.
        public var indirectEnabled: Bool
        /// "N entry point(s) across M categor(y|ies)", with the cap warning when it applies.
        public var countText: String
        public var truncated: Bool
        public var groups: [EntryGroupDTO]
        public var trace: EntryTraceDTO?

        public init(title: String, busy: Bool, progressText: String, progressDone: Int, progressTotal: Int,
                    indirectEnabled: Bool, countText: String, truncated: Bool, groups: [EntryGroupDTO],
                    trace: EntryTraceDTO?) {
            self.title = title
            self.busy = busy
            self.progressText = progressText
            self.progressDone = progressDone
            self.progressTotal = progressTotal
            self.indirectEnabled = indirectEnabled
            self.countText = countText
            self.truncated = truncated
            self.groups = groups
            self.trace = trace
        }
    }

    // MARK: - State (guarded by `lock`)

    private let lock = NSLock()
    private var primaryGroups: [EntryGroup] = []
    private var indirectGroups: [EntryGroup] = []
    private var indirectCollected = false
    private var showIndirect = false
    private var truncated = false
    private var sitesByID: [String: EntrySite] = [:]
    private var activeIndex: ProjectSourceIndex?
    private var activeTracer: VariableFlowTracer?
    private var busyMessage: String?
    private var progressDone = 0
    private var progressTotal = 0
    /// Bumped by every request; a job publishes only while its generation is still the newest.
    private var generation = 0
    private var cancellation: VariableFlowCancellation?
    private var lastTrace: EntryTraceDTO?

    private init() {}

    // MARK: - Queries

    /// The current result set.
    public func state() -> EntryPointsStateDTO {
        lock.lock()
        defer { lock.unlock() }
        return snapshot()
    }

    // MARK: - Actions

    /// Finds the primary entry points of the open project (`begin` + `collectPrimary`). Builds the
    /// source index first when the workspace has none for this folder. The job result is the state.
    public func start() throws -> String {
        let root = try KarmaWorkspace.shared.requireRoot().standardizedFileURL
        lock.lock()
        resetResults()
        generation += 1
        let gen = generation
        cancellation?.cancel()
        let token = VariableFlowCancellation()
        cancellation = token
        busyMessage = "Finding entry points…"
        progressDone = 0
        progressTotal = 0
        let jobID = KarmaJobCenter.shared.start(kind: "entry-points") { _ in
            let index = self.sourceIndex(for: root, token: token, generation: gen)
            guard let index = index, !token.isCancelled, !index.wasCancelled else {
                self.finishBusy(generation: gen)
                return KarmaJSON.data(self.state())
            }
            self.setBusyMessage("Finding entry points…", generation: gen)
            let groups = EntryPointCollector.collect(sourceIndex: index, includeIndirect: false) { done, total in
                self.setProgress(done: done, total: total, generation: gen)
            }
            let truncatedNow = EntryPointCollector.truncationWarning
            self.lock.lock()
            if gen == self.generation {
                self.primaryGroups = groups
                self.indirectGroups = []
                self.indirectCollected = false
                self.showIndirect = false
                self.truncated = truncatedNow
                self.activeIndex = index
                self.activeTracer = VariableFlowTracer(sourceIndex: index)
                self.rebuildSites()
                self.busyMessage = nil
                self.cancellation = nil
            }
            self.lock.unlock()
            return KarmaJSON.data(self.state())
        }
        lock.unlock()
        return jobID
    }

    /// Turns the indirect tier on or off. The first time it is turned on, the tier is collected
    /// (`toggleIndirect` + `collectIndirect`). The job result is the state.
    public func setIndirect(_ on: Bool) throws -> String {
        let root = try KarmaWorkspace.shared.requireRoot().standardizedFileURL
        lock.lock()
        showIndirect = on
        let needsCollection = on && !indirectCollected && activeIndex != nil
        generation += 1
        let gen = generation
        if needsCollection {
            cancellation?.cancel()
        }
        let token = VariableFlowCancellation()
        if needsCollection {
            cancellation = token
            busyMessage = "Finding indirect entries…"
            progressDone = 0
            progressTotal = 0
        }
        let jobID = KarmaJobCenter.shared.start(kind: "entry-points-indirect") { _ in
            guard needsCollection else { return KarmaJSON.data(self.state()) }
            let index = self.sourceIndex(for: root, token: token, generation: gen)
            guard let index = index, !token.isCancelled, !index.wasCancelled else {
                self.finishBusy(generation: gen)
                return KarmaJSON.data(self.state())
            }
            let groups = EntryPointCollector.collect(sourceIndex: index, includeIndirect: true) { done, total in
                self.setProgress(done: done, total: total, generation: gen)
            }
            self.lock.lock()
            if gen == self.generation {
                self.indirectGroups = groups.filter { $0.confidence == .indirect }
                self.indirectCollected = true
                self.busyMessage = nil
                self.cancellation = nil
                self.rebuildSites()
            }
            self.lock.unlock()
            return KarmaJSON.data(self.state())
        }
        lock.unlock()
        return jobID
    }

    /// Traces the flow of the entry `siteID` (`trace(site:)`): the variable's uses across calls, or a
    /// single box for an inline site. The job result is the `EntryTraceDTO`.
    public func trace(siteID: String) throws -> String {
        lock.lock()
        guard let site = sitesByID[siteID] else {
            lock.unlock()
            throw KarmaServiceError.notFound("No entry point with id \(siteID).")
        }
        let tracer = activeTracer
        let root = KarmaWorkspace.shared.read { $0.root }
        lock.unlock()

        let jobID = KarmaJobCenter.shared.start(kind: "entry-points-trace") { _ in
            let dto: EntryTraceDTO
            if let variable = site.entryVariable {
                let engine = tracer ?? Self.fallbackTracer(root: root)
                dto = self.traceFlow(site: site, siteID: siteID, variable: variable, tracer: engine)
            } else {
                dto = self.inlineTrace(site: site, siteID: siteID)
            }
            self.lock.lock()
            self.lastTrace = dto
            self.lock.unlock()
            return KarmaJSON.data(dto)
        }
        return jobID
    }

    // MARK: - Private: jobs

    /// The index the window would use: the workspace's when it is for this folder, else one built now.
    private func sourceIndex(for root: URL, token: VariableFlowCancellation, generation gen: Int) -> ProjectSourceIndex? {
        if let shared = KarmaWorkspace.shared.read({ $0.sourceIndex }), shared.root.standardizedFileURL == root {
            return shared
        }
        setBusyMessage("Building the project index…", generation: gen)
        return ProjectSourceIndex(projectRoot: root, cancellation: token) { done, total in
            self.setProgress(done: done, total: total, generation: gen)
        }
    }

    private static func fallbackTracer(root: URL?) -> VariableFlowTracer? {
        guard let root = root else { return nil }
        return VariableFlowTracer(projectRoot: root)
    }

    private func setBusyMessage(_ message: String, generation gen: Int) {
        lock.lock()
        if gen == generation { busyMessage = message }
        lock.unlock()
    }

    private func setProgress(done: Int, total: Int, generation gen: Int) {
        lock.lock()
        if gen == generation {
            progressDone = done
            progressTotal = total
        }
        lock.unlock()
    }

    /// Ends the busy state of a job that did not finish its work.
    private func finishBusy(generation gen: Int) {
        lock.lock()
        if gen == generation {
            busyMessage = nil
            cancellation = nil
        }
        lock.unlock()
    }

    // MARK: - Private: tracing

    /// Mirrors `EntryPointsWindowController.displayTrace`: names the boxes, adds the origin box and builds the caption.
    private func traceFlow(site: EntrySite, siteID: String, variable: String, tracer: VariableFlowTracer?) -> EntryTraceDTO {
        let originLabel = site.origin == .internet ? "Remote" : "Local"
        guard let tracer = tracer else {
            return EntryTraceDTO(siteID: siteID, caption: "Project index is not ready.", originLabel: originLabel,
                                 nodes: [], edges: [])
        }
        let result = tracer.trace(variableName: variable, in: site.fileURL, charIndex: site.charIndex)
        guard !result.nodes.isEmpty else {
            return EntryTraceDTO(siteID: siteID,
                                 caption: "No flow found for “\(variable)” from \(site.fileURL.lastPathComponent):\(site.line).",
                                 originLabel: originLabel, nodes: [], edges: [])
        }

        var names: [String: String] = [:]
        var used: Set<String> = []
        for node in result.nodes.sorted(by: { $0.depth < $1.depth }) {
            var name = node.functionName
            if used.contains(name) { name = "\(node.functionName) (\(node.fileHint))" }
            var candidate = name
            var n = 2
            while used.contains(candidate) { candidate = "\(name) \(n)"; n += 1 }
            used.insert(candidate)
            names[node.id] = candidate
        }

        var nodes: [EntryTraceNodeDTO] = []
        for node in result.nodes {
            guard let display = names[node.id] else { continue }
            // The start frame lands on the selected entry's own line (see the window's comment).
            let line = (node.isStart && node.fileURL == site.fileURL) ? site.line : (node.lines.first ?? 1)
            nodes.append(EntryTraceNodeDTO(name: display, path: node.fileURL.path, line: line,
                                           isStart: node.isStart, isOrigin: false))
        }

        var edges: [EntryTraceEdgeDTO] = []
        for edge in result.edges {
            guard let a = names[edge.from], let b = names[edge.to], a != b else { continue }
            edges.append(EntryTraceEdgeDTO(from: a, to: b))
        }

        let startName = result.nodes.first(where: { $0.isStart }).flatMap { names[$0.id] }
        if let startName = startName {
            nodes.insert(EntryTraceNodeDTO(name: originLabel, path: nil, line: nil, isStart: false, isOrigin: true), at: 0)
            edges.insert(EntryTraceEdgeDTO(from: originLabel, to: startName), at: 0)
        }

        let flowCount = result.edges.count
        let fileCount = Set(result.nodes.map { $0.fileURL.path }).count
        let caption = "Flow of “\(variable)” (\(site.apiPath)) — \(flowCount) hop\(flowCount == 1 ? "" : "s") across \(fileCount) file\(fileCount == 1 ? "" : "s"), coming in from \(originLabel). "
            + "Click any node to open it."
        return EntryTraceDTO(siteID: siteID, caption: caption, originLabel: originLabel, nodes: nodes, edges: edges)
    }

    /// Mirrors `EntryPointsWindowController.displayInline`: one box for the site, joined to its origin.
    private func inlineTrace(site: EntrySite, siteID: String) -> EntryTraceDTO {
        let originLabel = site.origin == .internet ? "Remote" : "Local"
        let nodeLabel = "\(site.fileURL.lastPathComponent):\(site.line)"
        let caption = "“\(site.apiName)” receives external \(originLabel.lowercased()) data here, but it's consumed inline (not stored in a variable), so there's no variable flow to trace. Click the box to open the source."
        return EntryTraceDTO(
            siteID: siteID,
            caption: caption,
            originLabel: originLabel,
            nodes: [
                EntryTraceNodeDTO(name: originLabel, path: nil, line: nil, isStart: false, isOrigin: true),
                EntryTraceNodeDTO(name: nodeLabel, path: site.fileURL.path, line: site.line, isStart: true, isOrigin: false),
            ],
            edges: [EntryTraceEdgeDTO(from: originLabel, to: nodeLabel)])
    }

    // MARK: - Private: state

    /// Caller must hold `lock`.
    private func resetResults() {
        primaryGroups = []
        indirectGroups = []
        indirectCollected = false
        showIndirect = false
        truncated = false
        sitesByID = [:]
        activeIndex = nil
        activeTracer = nil
        lastTrace = nil
    }

    /// Caller must hold `lock`.
    private func rebuildSites() {
        var sites: [String: EntrySite] = [:]
        for group in primaryGroups + indirectGroups {
            for site in group.sites {
                sites[Self.siteID(site)] = site
            }
        }
        sitesByID = sites
    }

    private static func siteID(_ site: EntrySite) -> String {
        "\(site.fileURL.path)#\(site.charIndex)"
    }

    /// Caller must hold `lock`.
    private func snapshot() -> EntryPointsStateDTO {
        let root = KarmaWorkspace.shared.read { $0.root }
        let groups = showIndirect ? primaryGroups + indirectGroups : primaryGroups
        let dtos = groups.map { group in
            EntryGroupDTO(
                id: "\(group.confidence)|\(group.origin)|\(group.category)",
                category: group.category,
                origin: group.origin == .internet ? "internet" : "local",
                confidence: group.confidence == .primary ? "primary" : "indirect",
                badge: Self.badge(group),
                title: "\(group.category) — \(group.sites.count) site\(group.sites.count == 1 ? "" : "s")",
                sites: group.sites.map { siteDTO($0, root: root) })
        }
        let siteCount = groups.reduce(0) { $0 + $1.sites.count }
        let groupCount = groups.count
        var count = "\(siteCount) entry point\(siteCount == 1 ? "" : "s") across \(groupCount) categor\(groupCount == 1 ? "y" : "ies")"
        if truncated { count += " — capped at \(EntryPointCollector.siteCap); run again after narrowing the project" }
        let busy = busyMessage != nil
        return EntryPointsStateDTO(
            title: busy ? "\(Self.titleText) — searching…" : Self.titleText,
            busy: busy,
            progressText: busy ? (progressTotal > 0 ? "\(progressDone) of \(progressTotal) source files" : (busyMessage ?? "")) : "",
            progressDone: progressDone,
            progressTotal: progressTotal,
            indirectEnabled: showIndirect,
            countText: count,
            truncated: truncated,
            groups: dtos,
            trace: lastTrace)
    }

    private static func badge(_ group: EntryGroup) -> String {
        switch (group.confidence, group.origin) {
        case (.primary, .internet): return "◉ remote"
        case (.primary, .local): return "◈ local"
        case (.indirect, _): return "~ indirect"
        }
    }

    private func siteDTO(_ site: EntrySite, root: URL?) -> EntrySiteDTO {
        let relative = Self.relativePath(of: site.fileURL, root: root)
        return EntrySiteDTO(
            id: Self.siteID(site),
            path: site.fileURL.path,
            relativePath: relative,
            line: site.line,
            column: site.column,
            apiName: site.apiName,
            apiPath: site.apiPath,
            category: site.category,
            origin: site.origin == .internet ? "internet" : "local",
            confidence: site.confidence == .primary ? "primary" : "indirect",
            entryVariable: site.entryVariable,
            snippet: site.snippet,
            displaySnippet: site.snippet.isEmpty ? "→ " + site.apiPath : site.snippet,
            label: "\(relative):\(site.line)",
            sourceKind: site.sourceKind)
    }

    /// The path relative to the project root, so files that share a name stay distinct.
    private static func relativePath(of url: URL, root: URL?) -> String {
        guard let root = root else { return url.lastPathComponent }
        let rootPath = root.standardizedFileURL.path
        if url.path.hasPrefix(rootPath + "/") {
            return String(url.path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}
