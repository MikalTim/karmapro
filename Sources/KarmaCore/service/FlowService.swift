// by cipher.org.uk
import Foundation

/// The graph features of the main window: the flow panel, the data-flow diagram, the variable
/// flow, reachability, complexity distribution, the backtrace analyser and class usage.
///
/// The diagram windows draw with AppKit font metrics, so each DTO carries the model the window
/// draws from (nodes, edges, flags, texts), not positions. The browser lays the diagrams out.
public enum FlowService {

    // MARK: - Flow panel (control-flow chart)

    /// One node of a control-flow chart (`ControlFlowParser.Node`).
    public struct FlowNodeDTO: Codable, Sendable {
        public var id: Int
        /// "entry", "exit", "block", "decision", "switch" or "join".
        public var kind: String
        /// The text drawn in the node: "START", "END", "" for joins, otherwise the statement or condition.
        public var label: String
        /// 1-based source line, nil when the node has no reliable position.
        public var line: Int?
        /// True when the node sits on a line that uses the traced variable (variable flow only).
        public var highlighted: Bool

        public init(id: Int, kind: String, label: String, line: Int?, highlighted: Bool) {
            self.id = id
            self.kind = kind
            self.label = label
            self.line = line
            self.highlighted = highlighted
        }
    }

    /// One edge of a control-flow chart.
    public struct FlowEdgeDTO: Codable, Sendable {
        public var from: Int
        public var to: Int
        /// "T", "F", a case label, or nil for plain sequential flow.
        public var branch: String?
        /// True for a loop back-edge.
        public var isBackEdge: Bool

        public init(from: Int, to: Int, branch: String?, isBackEdge: Bool) {
            self.from = from
            self.to = to
            self.branch = branch
            self.isBackEdge = isBackEdge
        }
    }

    /// The flowchart of one function.
    public struct FlowChartDTO: Codable, Sendable {
        public var nodes: [FlowNodeDTO]
        public var edges: [FlowEdgeDTO]

        public init(nodes: [FlowNodeDTO], edges: [FlowEdgeDTO]) {
            self.nodes = nodes
            self.edges = edges
        }
    }

    /// What the flow panel shows for a function. When the function cannot be charted,
    /// `complexity`, `lineCount` and `chart` are nil and the panel shows "Cyclomatic complexity: —".
    public struct FlowDTO: Codable, Sendable {
        public var functionName: String
        public var complexity: Int?
        /// Number of lines in the file.
        public var lineCount: Int?
        /// Functions the function calls, in call order (`Functions called (n): …`).
        public var callees: [String]
        public var chart: FlowChartDTO?

        public init(functionName: String, complexity: Int?, lineCount: Int?, callees: [String], chart: FlowChartDTO?) {
            self.functionName = functionName
            self.complexity = complexity
            self.lineCount = lineCount
            self.callees = callees
            self.chart = chart
        }
    }

    // MARK: - Diagram model shared by the call and data-flow diagrams

    /// One node of a call/data-flow diagram.
    public struct GraphNodeDTO: Codable, Sendable {
        public var name: String
        /// Source location for a click, when the node is a project function.
        public var path: String?
        public var line: Int?
        /// Origin box (Remote, Local, Topmost, or the instantiating class): drawn square.
        public var isOrigin: Bool
        /// Forward (callee) overlay box: grey with black text.
        public var isGreyed: Bool
        /// Amber outline: the topmost boxes of an unverified reachability walk.
        public var isOutlined: Bool
        /// Origin box colour name ("orange"); nil means the accent colour.
        public var originColor: String?

        public init(name: String, path: String?, line: Int?, isOrigin: Bool, isGreyed: Bool, isOutlined: Bool, originColor: String?) {
            self.name = name
            self.path = path
            self.line = line
            self.isOrigin = isOrigin
            self.isGreyed = isGreyed
            self.isOutlined = isOutlined
            self.originColor = originColor
        }
    }

    /// A directed edge between two diagram nodes, by node name.
    public struct GraphEdgeDTO: Codable, Sendable {
        public var from: String
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// The inputs `DataFlowDiagramView` takes: the graph, its two edge kinds and the layout inputs.
    public struct DiagramGraphDTO: Codable, Sendable {
        public var nodes: [GraphNodeDTO]
        /// Solid call edges (used for layout ranking as well).
        public var callEdges: [GraphEdgeDTO]
        /// Animated dashed data-flow edges.
        public var dataEdges: [GraphEdgeDTO]
        /// The node drawn highlighted.
        public var highlight: String?
        /// "leftToRight" or "topToBottom".
        public var layoutDirection: String
        /// Nodes pinned to the top rank in "topToBottom" layouts.
        public var layoutSourceNodes: [String]
        /// When set, the butterfly layout centred on this node.
        public var layoutCenterNode: String?
        /// When set, only these nodes (and the neighbours revealed from them) are drawn.
        public var focusNodes: [String]?
        /// True when only the dashed data edges are drawn (call edges are for layout only).
        public var animatedOnlyEdges: Bool

        public init(nodes: [GraphNodeDTO], callEdges: [GraphEdgeDTO], dataEdges: [GraphEdgeDTO], highlight: String?,
                    layoutDirection: String, layoutSourceNodes: [String], layoutCenterNode: String?,
                    focusNodes: [String]?, animatedOnlyEdges: Bool) {
            self.nodes = nodes
            self.callEdges = callEdges
            self.dataEdges = dataEdges
            self.highlight = highlight
            self.layoutDirection = layoutDirection
            self.layoutSourceNodes = layoutSourceNodes
            self.layoutCenterNode = layoutCenterNode
            self.focusNodes = focusNodes
            self.animatedOnlyEdges = animatedOnlyEdges
        }
    }

    // MARK: - Data flow

    /// The data-flow window of one function.
    public struct DataFlowDTO: Codable, Sendable {
        public var functionName: String
        public var windowTitle: String
        public var title: String
        public var caption: String
        /// Shown instead of the diagram when no flow was found in the file.
        public var emptyMessage: String?
        /// Nil when `emptyMessage` is set.
        public var graph: DiagramGraphDTO?

        public init(functionName: String, windowTitle: String, title: String, caption: String,
                    emptyMessage: String?, graph: DiagramGraphDTO?) {
            self.functionName = functionName
            self.windowTitle = windowTitle
            self.title = title
            self.caption = caption
            self.emptyMessage = emptyMessage
            self.graph = graph
        }
    }

    // MARK: - Variable flow

    /// A source line and its text (a use of the traced variable, or a callee line).
    public struct LineTextDTO: Codable, Sendable {
        public var line: Int
        public var text: String

        public init(line: Int, text: String) {
            self.line = line
            self.text = text
        }
    }

    /// One frame of the variable trace (`VariableFlowNode`).
    public struct VariableNodeDTO: Codable, Sendable {
        public var id: String
        public var functionName: String
        /// The identifier traced inside this frame.
        public var variableName: String
        public var path: String
        public var fileHint: String
        /// Argument-passing hops from the start frame (0 = start frame).
        public var depth: Int
        /// The lines where the identifier is used, in source order, each with its text.
        public var uses: [LineTextDTO]
        public var isStart: Bool

        public init(id: String, functionName: String, variableName: String, path: String, fileHint: String,
                    depth: Int, uses: [LineTextDTO], isStart: Bool) {
            self.id = id
            self.functionName = functionName
            self.variableName = variableName
            self.path = path
            self.fileHint = fileHint
            self.depth = depth
            self.uses = uses
            self.isStart = isStart
        }
    }

    /// A call from one trace frame to a callee frame, at the caller's call-site line.
    public struct VariableEdgeDTO: Codable, Sendable {
        public var from: String
        public var to: String
        public var callLine: Int

        public init(from: String, to: String, callLine: Int) {
            self.from = from
            self.to = to
            self.callLine = callLine
        }
    }

    /// One callee box (`VariableFlowCallout`) and the boxes nested inside it.
    public struct CalloutDTO: Codable, Sendable {
        public var callLine: Int
        public var functionName: String
        public var variableName: String
        public var path: String
        public var fileHint: String
        public var useLines: [LineTextDTO]
        public var children: [CalloutDTO]

        public init(callLine: Int, functionName: String, variableName: String, path: String, fileHint: String,
                    useLines: [LineTextDTO], children: [CalloutDTO]) {
            self.callLine = callLine
            self.functionName = functionName
            self.variableName = variableName
            self.path = path
            self.fileHint = fileHint
            self.useLines = useLines
            self.children = children
        }
    }

    /// The variable-flow window: the trace result plus the enclosing function's flowchart.
    public struct VariableFlowDTO: Codable, Sendable {
        public var variableName: String
        public var startFunction: String
        public var windowTitle: String
        public var title: String
        public var caption: String
        public var warnings: [String]
        public var nodes: [VariableNodeDTO]
        public var edges: [VariableEdgeDTO]
        /// The callee boxes of the start frame (the children of the start box).
        public var callouts: [CalloutDTO]
        /// The enclosing function's flowchart; nil when it cannot be charted, then the start frame is drawn as a plain box.
        public var chart: FlowChartDTO?

        public init(variableName: String, startFunction: String, windowTitle: String, title: String, caption: String,
                    warnings: [String], nodes: [VariableNodeDTO], edges: [VariableEdgeDTO],
                    callouts: [CalloutDTO], chart: FlowChartDTO?) {
            self.variableName = variableName
            self.startFunction = startFunction
            self.windowTitle = windowTitle
            self.title = title
            self.caption = caption
            self.warnings = warnings
            self.nodes = nodes
            self.edges = edges
            self.callouts = callouts
            self.chart = chart
        }
    }

    // MARK: - Reachability

    /// The reachability window of one function.
    public struct ReachabilityDTO: Codable, Sendable {
        public var functionName: String
        public var windowTitle: String
        public var title: String
        /// The explanation text, including the "no path" text and the warnings.
        public var caption: String
        public var remoteReachable: Bool
        public var localReachable: Bool
        /// True when no entry point reaches the function; the diagram then tops out with the amber "Topmost" box.
        public var unverified: Bool
        /// Nil when the walk found no function ("No reachability data").
        public var graph: DiagramGraphDTO?

        public init(functionName: String, windowTitle: String, title: String, caption: String,
                    remoteReachable: Bool, localReachable: Bool, unverified: Bool, graph: DiagramGraphDTO?) {
            self.functionName = functionName
            self.windowTitle = windowTitle
            self.title = title
            self.caption = caption
            self.remoteReachable = remoteReachable
            self.localReachable = localReachable
            self.unverified = unverified
            self.graph = graph
        }
    }

    // MARK: - Complexity distribution

    /// One function plotted by the complexity chart.
    public struct ComplexityPointDTO: Codable, Sendable {
        public var name: String
        public var complexity: Int
        public var line: Int
        public var path: String

        public init(name: String, complexity: Int, line: Int, path: String) {
            self.name = name
            self.complexity = complexity
            self.line = line
            self.path = path
        }
    }

    /// The complexity-distribution window: title, summary, empty-state text and the plotted points in source order.
    public struct ComplexityDTO: Codable, Sendable {
        public var windowTitle: String
        public var summary: String
        /// Shown in the plot area when there are no points.
        public var placeholder: String
        public var points: [ComplexityPointDTO]

        public init(windowTitle: String, summary: String, placeholder: String, points: [ComplexityPointDTO]) {
            self.windowTitle = windowTitle
            self.summary = summary
            self.placeholder = placeholder
            self.points = points
        }
    }

    // MARK: - Backtrace analyser

    /// One parsed frame. `path` is nil when the file is not part of the open project.
    public struct BacktraceFrameDTO: Codable, Sendable {
        public var functionName: String
        public var fileHint: String
        public var path: String?
        public var line: Int

        public init(functionName: String, fileHint: String, path: String?, line: Int) {
            self.functionName = functionName
            self.fileHint = fileHint
            self.path = path
            self.line = line
        }
    }

    /// The alert shown when some frames are not in the open project.
    public struct BacktraceWarningDTO: Codable, Sendable {
        public var messageText: String
        public var informativeText: String

        public init(messageText: String, informativeText: String) {
            self.messageText = messageText
            self.informativeText = informativeText
        }
    }

    /// The backtrace analyser's result.
    public struct BacktraceDTO: Codable, Sendable {
        public var frames: [BacktraceFrameDTO]
        public var status: String
        /// Nil when every frame resolved.
        public var warning: BacktraceWarningDTO?

        public init(frames: [BacktraceFrameDTO], status: String, warning: BacktraceWarningDTO?) {
            self.frames = frames
            self.status = status
            self.warning = warning
        }
    }

    // MARK: - Class usage

    /// One `new ClassName(` site.
    public struct ClassUsageSiteDTO: Codable, Sendable {
        public var path: String
        public var line: Int
        /// The text from the match on (up to 80 characters).
        public var snippet: String

        public init(path: String, line: Int, snippet: String) {
            self.path = path
            self.line = line
            self.snippet = snippet
        }
    }

    /// The class-usage window: the class node with one node per instantiation site.
    public struct ClassUsageDTO: Codable, Sendable {
        public var className: String
        public var windowTitle: String
        public var title: String
        public var status: String
        /// Shown instead of the diagram when there are no instantiations.
        public var emptyMessage: String?
        public var sites: [ClassUsageSiteDTO]
        /// Nil when there are no instantiations.
        public var graph: DiagramGraphDTO?

        public init(className: String, windowTitle: String, title: String, status: String,
                    emptyMessage: String?, sites: [ClassUsageSiteDTO], graph: DiagramGraphDTO?) {
            self.className = className
            self.windowTitle = windowTitle
            self.title = title
            self.status = status
            self.emptyMessage = emptyMessage
            self.sites = sites
            self.graph = graph
        }
    }

    // MARK: - Flow panel

    /// `GET /api/flow?path=&function=`: the complexity and flowchart of a function, as the flow panel shows them.
    /// The overload whose name range contains `location` is analysed, as the panel does with the definition the user
    /// clicked; without a match (or without `location`) the first definition with that name is used.
    public static func flow(path: String, function: String, location: Int? = nil) throws -> FlowDTO {
        let url = URL(fileURLWithPath: path)
        let source = try readText(url)
        let ext = url.pathExtension
        let defs = diagramDefinitions(source: source, ext: ext)
        let overloads = defs.filter { $0.name == function }
        let clicked = location.flatMap { at in overloads.first { NSLocationInRange(at, $0.nameRange) } }
        guard let def = clicked ?? overloads.first,
              let flow = ControlFlowParser.analyze(source: source, ext: ext, functionName: function, definition: def) else {
            return FlowDTO(functionName: function, complexity: nil, lineCount: nil, callees: [], chart: nil)
        }
        let calls = diagramCallGraph(source: source, definitions: defs).calls
        let callees = calls.filter { $0.from == function }.map { $0.to }
        let chart = makeChart(flow, source: source, ext: ext, bodyRange: def.bodyRange, startLines: [])
        return FlowDTO(functionName: function,
                       complexity: flow.complexity,
                       lineCount: source.components(separatedBy: "\n").count,
                       callees: callees,
                       chart: chart)
    }

    // MARK: - Data flow

    /// `GET /api/dataflow?path=&function=`: the call and data-flow neighbourhood of a function within its file.
    /// Only the selected function, its direct callers and its direct callees are kept.
    public static func dataFlow(path: String, function: String) throws -> DataFlowDTO {
        let url = URL(fileURLWithPath: path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw KarmaServiceError.notFound("Unable to read file")
        }
        let defs = diagramDefinitions(source: text, ext: url.pathExtension)
        let (calls, data) = diagramCallGraph(source: text, definitions: defs)

        let graph = CallGraph()
        for (from, to) in calls { graph.addCall(from: from, to: to) }
        for (from, to) in data { graph.addDataFlow(from: from, to: to) }
        // Only keep nodes that are actually defined functions in this file.
        for def in defs { _ = graph.node(for: def.name) }
        graph.pruneTo(defined: Set(defs.map { $0.name }))

        let centerName: String?
        if defs.contains(where: { $0.name == function }) {
            centerName = function
        } else {
            centerName = graph.functionNames.first
        }

        // Direct-neighbour scope: the selected function plus its immediate callers and callees in this file.
        if let center = centerName {
            var keep: Set<String> = [center]
            for (from, to) in calls where graph.hasNode(from) && graph.hasNode(to) {
                if to == center || from == center {
                    keep.insert(from)
                    keep.insert(to)
                }
            }
            graph.pruneTo(defined: keep)
        }

        let windowTitle = "Dataflow: \(function) — \(url.lastPathComponent)"
        let title = "Dataflow around “\(function)”"
        let caption = "Callers to the left · Callees to the right · Solid arrows: function calls · Animated dashed arrows: data flow · Direct callees only"

        let visibleCalls = calls.filter { graph.hasNode($0.0) && graph.hasNode($0.1) }
        let visibleData = data.filter { graph.hasNode($0.0) && graph.hasNode($0.1) }
        guard !visibleCalls.isEmpty || !visibleData.isEmpty else {
            return DataFlowDTO(functionName: function, windowTitle: windowTitle, title: title, caption: caption,
                               emptyMessage: "No direct flow was identified within the same file, try the reachability diagram if you want cross-file",
                               graph: nil)
        }
        let diagram = DiagramGraphDTO(nodes: plainNodes(graph),
                                      callEdges: visibleCalls.map { GraphEdgeDTO(from: $0.0, to: $0.1) },
                                      dataEdges: visibleData.map { GraphEdgeDTO(from: $0.0, to: $0.1) },
                                      highlight: centerName,
                                      layoutDirection: "leftToRight",
                                      layoutSourceNodes: [],
                                      layoutCenterNode: centerName,
                                      focusNodes: nil,
                                      animatedOnlyEdges: false)
        return DataFlowDTO(functionName: function, windowTitle: windowTitle, title: title, caption: caption,
                           emptyMessage: nil, graph: diagram)
    }

    /// `GET /api/file/dataflow?path=&function=`: the bottom pane of the source viewer
    /// (`SourceViewer.showFunctionDataflow`): the clicked function plus every function of the same file it
    /// reaches through calls, with the call and data edges among them. `graph` is nil when there is nothing
    /// to draw (the pane is hidden).
    public static func functionDataFlow(path: String, function: String) throws -> DataFlowDTO {
        let url = URL(fileURLWithPath: path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw KarmaServiceError.notFound("Unable to read file")
        }
        let defs = diagramDefinitions(source: text, ext: url.pathExtension)
        let (calls, data) = diagramCallGraph(source: text, definitions: defs)
        let defined = Set(defs.map { $0.name })

        var reachable: Set<String> = [function]
        var frontier = [function]
        while let current = frontier.popLast() {
            for (from, to) in calls where from == current && defined.contains(to) && !reachable.contains(to) {
                reachable.insert(to)
                frontier.append(to)
            }
        }

        let graph = CallGraph()
        for (from, to) in calls where reachable.contains(from) && reachable.contains(to) { graph.addCall(from: from, to: to) }
        for (from, to) in data where reachable.contains(from) && reachable.contains(to) { graph.addDataFlow(from: from, to: to) }

        let title = "Dataflow within file \u{2014} \(function)"
        let windowTitle = "Dataflow: \(function) \u{2014} \(url.lastPathComponent)"
        guard !graph.nodes.isEmpty else {
            return DataFlowDTO(functionName: function, windowTitle: windowTitle, title: title, caption: "",
                               emptyMessage: "", graph: nil)
        }
        let diagram = DiagramGraphDTO(nodes: plainNodes(graph),
                                      callEdges: calls.filter { graph.hasNode($0.0) && graph.hasNode($0.1) }
                                          .map { GraphEdgeDTO(from: $0.0, to: $0.1) },
                                      dataEdges: data.filter { graph.hasNode($0.0) && graph.hasNode($0.1) }
                                          .map { GraphEdgeDTO(from: $0.0, to: $0.1) },
                                      highlight: function,
                                      layoutDirection: "leftToRight",
                                      layoutSourceNodes: [],
                                      layoutCenterNode: nil,
                                      focusNodes: nil,
                                      animatedOnlyEdges: false)
        return DataFlowDTO(functionName: function, windowTitle: windowTitle, title: title, caption: "",
                           emptyMessage: nil, graph: diagram)
    }

    // MARK: - Variable flow

    /// `POST /api/variable-flow {path, location, variable}`: traces `variable` from the position `location`
    /// (a UTF-16 offset in `path`) across the project. Returns the job id; the result is a `VariableFlowDTO`.
    public static func variableFlow(path: String, location: Int, variable: String) throws -> String {
        let (root, generation) = try projectSnapshot()
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        return KarmaJobCenter.shared.start(kind: "variable-flow") { context in
            guard let tracer = FlowService.tracer(root: root, generation: generation, context: context) else { return nil }
            let result = tracer.trace(variableName: variable, in: fileURL, charIndex: location)
            return KarmaJSON.data(FlowService.variableFlowDTO(result))
        }
    }

    // MARK: - Reachability

    /// `POST /api/reachability {path, function}`: the project-wide caller chain of a function and its direct callees.
    /// Returns the job id; the result is a `ReachabilityDTO`.
    public static func reachability(path: String, function: String) throws -> String {
        let (root, generation) = try projectSnapshot()
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        return KarmaJobCenter.shared.start(kind: "reachability") { context in
            guard let graph = FlowService.callGraph(root: root, generation: generation, context: context) else { return nil }
            let result = graph.reachability(of: function, in: fileURL)
            return KarmaJSON.data(FlowService.reachabilityDTO(result))
        }
    }

    // MARK: - Complexity distribution

    /// `GET /api/complexity?path=`: every function of one file, as `ComplexityScatterWindowController.load(fileURL:)` shows it.
    public static func complexity(path: String) throws -> ComplexityDTO {
        try fileComplexity(path)
    }

    /// `POST /api/complexity {path?}`: the whole project when `path` is nil (the project scan runs off the main
    /// thread in AppKit, so it is a job), or one file. Returns the job id; the result is a `ComplexityDTO`.
    public static func complexityJob(path: String?) throws -> String {
        if let path = path {
            // Validate the file before starting, so a missing file fails at once.
            _ = try readText(URL(fileURLWithPath: path))
            return KarmaJobCenter.shared.start(kind: "complexity") { _ in
                let dto = try FlowService.fileComplexity(path)
                return KarmaJSON.data(dto)
            }
        }
        let root = try KarmaWorkspace.shared.requireRoot()
        return KarmaJobCenter.shared.start(kind: "complexity") { context in
            FlowService.projectComplexity(root: root, context: context)
        }
    }

    // MARK: - Backtrace analyser

    /// `POST /api/backtrace {text}`: parses a pasted stacktrace and resolves each frame's file inside the open project.
    /// Throws `KarmaServiceError.invalid` with the window's status text when there is nothing to analyse.
    public static func backtrace(text: String) throws -> BacktraceDTO {
        let root = try KarmaWorkspace.shared.requireRoot()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KarmaServiceError.invalid("Paste a stacktrace first.")
        }
        let parsed = BacktraceParser().parse(text)
        guard !parsed.isEmpty else {
            throw KarmaServiceError.invalid("No stacktrace frames could be parsed. Check the format.")
        }

        var frames: [BacktraceFrameDTO] = []
        var unresolvedCount = 0
        for frame in parsed {
            let path = resolveBacktracePath(frame.fileHint, root: root)
            if path == nil { unresolvedCount += 1 }
            frames.append(BacktraceFrameDTO(functionName: frame.functionName, fileHint: frame.fileHint,
                                            path: path, line: frame.line))
        }

        guard unresolvedCount > 0 else {
            return BacktraceDTO(frames: frames,
                                status: "Parsed \(frames.count) frame(s) — all files resolved. Click a frame to jump to its source.",
                                warning: nil)
        }
        let warning = BacktraceWarningDTO(
            messageText: "Some files were not found in the open project",
            informativeText: "\(unresolvedCount) of \(frames.count) frame(s) reference source files that do not exist in the currently open project. The backtrace must come from the source code of the open project.")
        return BacktraceDTO(frames: frames,
                            status: "Parsed \(frames.count) frame(s) — \(unresolvedCount) not found in the open project. The backtrace must come from the open project's source.",
                            warning: warning)
    }

    // MARK: - Class usage

    /// `POST /api/class-usage {className}`: every `new ClassName(` in the project's Java and C# files.
    /// Returns the job id; the result is a `ClassUsageDTO`.
    public static func classUsage(className: String) throws -> String {
        let root = try KarmaWorkspace.shared.requireRoot()
        return KarmaJobCenter.shared.start(kind: "class-usage") { _ in
            let occurrences = ClassUsageScanner.scanInstantiations(of: className, in: root)
            return KarmaJSON.data(FlowService.classUsageDTO(className: className, occurrences: occurrences))
        }
    }

    // MARK: - Flowchart helpers

    /// `ControlFlowParser.Node.Kind` as the raw kind string and the text the node shows (`FlowChartView.nodeLabel`).
    private static func describe(_ kind: ControlFlowParser.Node.Kind) -> (kind: String, label: String) {
        switch kind {
        case .entry: return ("entry", "START")
        case .exit: return ("exit", "END")
        case .block(let text): return ("block", text)
        case .decision(let text): return ("decision", text)
        case .switchCase(let text): return ("switch", text)
        case .join: return ("join", "")
        }
    }

    /// Converts a chart to its DTO. The 1-based line of each node comes from the node's line
    /// when the parser recorded one, otherwise from its offset within `bodyRange`.
    private static func makeChart(_ flow: ControlFlowParser, source: String, ext: String,
                                  bodyRange: NSRange, startLines: Set<Int>) -> FlowChartDTO {
        let indentation = DiagramLanguage.from(ext: ext)?.usesIndentation == true
        let nodes = flow.nodes.map { node -> FlowNodeDTO in
            let described = describe(node.kind)
            let line = node.sourceLine ?? ControlFlowParser.line(forOffset: node.loc,
                                                                 bodyRange: bodyRange,
                                                                 in: source,
                                                                 indentationNormalized: indentation)
            let highlighted = line.map { startLines.contains($0) } ?? false
            return FlowNodeDTO(id: node.id, kind: described.kind, label: described.label,
                               line: line, highlighted: highlighted)
        }
        let edges = flow.edges.map { FlowEdgeDTO(from: $0.from, to: $0.to, branch: $0.branch, isBackEdge: $0.isBackEdge) }
        return FlowChartDTO(nodes: nodes, edges: edges)
    }

    // MARK: - Variable flow helpers

    private static func variableFlowDTO(_ result: VariableFlowResult) -> VariableFlowDTO {
        let name = result.variableName
        let title: String
        let caption: String
        if result.nodes.isEmpty {
            title = "No flow found for “\(name)”"
            let joined = result.warnings.joined(separator: " ")
            caption = joined.isEmpty ? "The variable was not found in the enclosing function." : joined
        } else {
            title = "Flow of “\(name)” in \(result.startFunction)"
            caption = variableCaption(result)
        }

        let nodes = result.nodes.map { node in
            VariableNodeDTO(id: node.id,
                            functionName: node.functionName,
                            variableName: node.variableName,
                            path: node.fileURL.path,
                            fileHint: node.fileHint,
                            depth: node.depth,
                            uses: zip(node.lines, node.useText).map { LineTextDTO(line: $0, text: $1) },
                            isStart: node.isStart)
        }
        let edges = result.edges.map { VariableEdgeDTO(from: $0.from, to: $0.to, callLine: $0.callLine) }
        let callouts = (VariableFlowTracer.calloutTree(from: result).first?.children ?? []).map { calloutDTO($0) }
        return VariableFlowDTO(variableName: name,
                               startFunction: result.startFunction,
                               windowTitle: "Variable Flow — \(name)",
                               title: title,
                               caption: caption,
                               warnings: result.warnings,
                               nodes: nodes,
                               edges: edges,
                               callouts: callouts,
                               chart: variableChart(result))
    }

    /// The caption of a non-empty trace (`VariableFlowWindowController.display`).
    private static func variableCaption(_ result: VariableFlowResult) -> String {
        let calloutCount = result.edges.count
        let fileCount = Set(result.nodes.map { $0.fileURL.path }).count
        var caption = "Flowchart of the enclosing function; highlighted statements use “\(result.variableName)”. "
        caption += "\(calloutCount) call-out\(calloutCount == 1 ? "" : "s") "
            + "across \(fileCount) file\(fileCount == 1 ? "" : "s"). "
        caption += "Blue “call” arrows leave the call; purple “return” arrows rejoin the caller. "
            + "Click a statement or source line to open it."
        if !result.warnings.isEmpty {
            caption += "\n\nNote: " + result.warnings.joined(separator: " ")
        }
        return caption
    }

    /// The enclosing function's flowchart, with the statements that use the traced variable highlighted.
    private static func variableChart(_ result: VariableFlowResult) -> FlowChartDTO? {
        guard !result.nodes.isEmpty, !result.startFunction.isEmpty else { return nil }
        let defs = diagramDefinitions(source: result.startFileSource, ext: result.startFileExt)
        guard let def = defs.first(where: { $0.name == result.startFunction }),
              let flow = ControlFlowParser.analyze(source: result.startFileSource, ext: result.startFileExt,
                                                   functionName: result.startFunction, definition: def) else {
            return nil
        }
        let startLines = Set(result.nodes.first(where: { $0.isStart })?.lines ?? [])
        return makeChart(flow, source: result.startFileSource, ext: result.startFileExt,
                         bodyRange: def.bodyRange, startLines: startLines)
    }

    private static func calloutDTO(_ callout: VariableFlowCallout) -> CalloutDTO {
        CalloutDTO(callLine: callout.callLine,
                   functionName: callout.functionName,
                   variableName: callout.variableName,
                   path: callout.fileURL.path,
                   fileHint: callout.fileHint,
                   useLines: callout.useLines.map { LineTextDTO(line: $0.line, text: $0.text) },
                   children: callout.children.map { calloutDTO($0) })
    }

    // MARK: - Reachability helpers

    /// The reachability diagram (`ReachabilityWindowController.present`): origin boxes for the entries the
    /// caller chain reaches (or the amber "Topmost" box), grey forward overlay, and one-path focus.
    private static func reachabilityDTO(_ result: ReachabilityResult) -> ReachabilityDTO {
        let windowTitle = "Reachability — \(result.functionName)"
        guard !result.nodes.isEmpty else {
            return ReachabilityDTO(functionName: result.functionName, windowTitle: windowTitle,
                                   title: "No reachability data",
                                   caption: result.warnings.joined(separator: " "),
                                   remoteReachable: result.remoteReachable, localReachable: result.localReachable,
                                   unverified: result.unverified, graph: nil)
        }

        let displayNames = Set(result.nodes.map { $0.displayName })
        var locations: [String: (path: String, line: Int)] = [:]
        for node in result.nodes { locations[node.displayName] = (node.fileURL.path, node.line) }
        var edges = result.edges.filter { displayNames.contains($0.0) && displayNames.contains($0.1) }
        let greyed = Set(result.nodes.filter { $0.isForwardOverlay }.map { $0.displayName })

        var sourceNodes = Set<String>()
        var outlined = Set<String>()
        var originColors: [String: String] = [:]
        if result.unverified {
            sourceNodes.insert("Topmost")
            for node in result.nodes where node.isTopmost && !node.isForwardOverlay {
                edges.insert(("Topmost", node.displayName), at: edges.startIndex)
            }
            outlined = Set(result.nodes.filter { $0.isTopmost && !$0.isForwardOverlay }.map { $0.displayName })
            originColors["Topmost"] = "orange"
        } else {
            if result.nodes.contains(where: { $0.entryKinds.contains(.remote) }) { sourceNodes.insert("Remote") }
            if result.nodes.contains(where: { $0.entryKinds.contains(.local) }) { sourceNodes.insert("Local") }
            for node in result.nodes {
                if node.entryKinds.contains(.remote), sourceNodes.contains("Remote") {
                    edges.insert(("Remote", node.displayName), at: edges.startIndex)
                }
                if node.entryKinds.contains(.local), sourceNodes.contains("Local") {
                    edges.insert(("Local", node.displayName), at: edges.startIndex)
                }
            }
        }

        // One-path focus: start on a single origin→start chain when there is a real path and the graph is busy.
        let startName = result.nodes.first(where: { $0.isStart })?.displayName
        var focus: [String]?
        if let start = startName,
           let path = ReachabilityPaths.shortestPath(from: sourceNodes, to: start, in: edges),
           path.count > 3 {
            focus = Array(Set(path)).sorted()
        }

        let names = displayNames.union(sourceNodes).sorted()
        let nodes = names.map { name in
            GraphNodeDTO(name: name,
                         path: locations[name]?.path,
                         line: locations[name]?.line,
                         isOrigin: sourceNodes.contains(name),
                         isGreyed: greyed.contains(name),
                         isOutlined: outlined.contains(name),
                         originColor: originColors[name])
        }
        let diagram = DiagramGraphDTO(nodes: nodes,
                                      callEdges: edges.map { GraphEdgeDTO(from: $0.0, to: $0.1) },
                                      dataEdges: [],
                                      highlight: startName,
                                      layoutDirection: "topToBottom",
                                      layoutSourceNodes: sourceNodes.sorted(),
                                      layoutCenterNode: nil,
                                      focusNodes: focus,
                                      animatedOnlyEdges: false)

        let fileCount = Set(result.nodes.map { $0.fileURL.path }).count
        let count = result.nodes.count
        var base = "\(count) function\(count == 1 ? "" : "s") "
            + "across \(fileCount) file\(fileCount == 1 ? "" : "s"). "
            + "Click any node to open it."
        if focus != nil {
            base += " Focused on one path — click a node's ⊕ to reveal its other callers/callees."
        }
        let note: String
        if result.unverified {
            note = "No path from any entry point in the project reaches “\(result.functionName)”. "
                + "The reverse chain dead-ends at the amber “Topmost” box — nothing else in the project calls those functions. "
        } else if result.remoteReachable && result.localReachable {
            note = "“\(result.functionName)” is reachable from both outside (Remote) and local (Local) entry points. "
        } else if result.remoteReachable {
            note = "“\(result.functionName)” is reachable from outside — the Remote box is a chain into it from an external entry point. "
        } else {
            note = "“\(result.functionName)” is reachable from a local entry point (main etc.) only — the Local box is the chain into it. "
        }
        let overlay = result.nodes.contains(where: { $0.isForwardOverlay }) ? " Grey boxes are the functions it calls directly. " : ""
        var caption = note + base + overlay
        if !result.warnings.isEmpty {
            caption += "\n\nNote: " + result.warnings.joined(separator: " ")
        }

        return ReachabilityDTO(functionName: result.functionName,
                               windowTitle: windowTitle,
                               title: "Reachability of “\(result.functionName)”",
                               caption: caption,
                               remoteReachable: result.remoteReachable,
                               localReachable: result.localReachable,
                               unverified: result.unverified,
                               graph: diagram)
    }

    // MARK: - Complexity helpers

    private static func fileComplexity(_ path: String) throws -> ComplexityDTO {
        let url = URL(fileURLWithPath: path)
        let source = try readText(url)
        let name = url.lastPathComponent
        let entries = ControlFlowParser.analyzeAll(source: source, ext: url.pathExtension)
        let summary: String
        if entries.isEmpty {
            summary = "\(name) — no functions found"
        } else {
            let complexities = entries.map { $0.complexity }
            let mean = complexities.reduce(0, +) / entries.count
            summary = "\(name) — \(entries.count) functions · mean complexity \(mean) · max \(complexities.max() ?? 0)"
        }
        return ComplexityDTO(windowTitle: "Complexity distribution — \(name)",
                             summary: summary,
                             placeholder: "No functions found in this file",
                             points: entries.map { ComplexityPointDTO(name: $0.name, complexity: $0.complexity,
                                                                      line: $0.line, path: url.path) })
    }

    /// Plots every function of every viewer-language file under `root`. Returns nil when the job was cancelled.
    private static func projectComplexity(root: URL, context: JobContext) -> Data? {
        let files = SourceTree.enumerate(extensions: ProjectSourceIndex.viewerExtensions, in: root)
            .sorted { $0.path < $1.path }
        let started = Date()
        var points: [ComplexityPointDTO] = []
        var busyFiles = 0
        for (index, url) in files.enumerated() {
            if context.isCancelled { return nil }
            context.progress(done: index, total: files.count, stage: "Analysing \(index) of \(files.count) files")
            guard let source = try? String(contentsOf: url, encoding: .utf8),
                  source.count <= ProjectSourceIndex.maxChars else { continue }
            for entry in ControlFlowParser.analyzeAll(source: source, ext: url.pathExtension) {
                points.append(ComplexityPointDTO(name: entry.name, complexity: entry.complexity,
                                                 line: entry.line, path: url.path))
            }
            busyFiles += 1
        }
        if context.isCancelled { return nil }

        let summary: String
        let placeholder: String
        if points.isEmpty {
            summary = "No functions found across \(files.count) files"
            placeholder = "No functions found in this project"
        } else {
            let complexities = points.map { $0.complexity }
            let mean = complexities.reduce(0, +) / points.count
            let seenFiles = Set(points.map { $0.path }).count
            let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
            summary = "\(root.lastPathComponent) — \(points.count) functions in \(seenFiles)/\(busyFiles) files · mean complexity \(mean) · max \(complexities.max() ?? 0) · \(elapsed)s"
            placeholder = ""
        }
        let dto = ComplexityDTO(windowTitle: "Complexity distribution — \(root.lastPathComponent)",
                                summary: summary, placeholder: placeholder, points: points)
        return KarmaJSON.data(dto)
    }

    // MARK: - Class usage helpers

    private static func classUsageDTO(className: String, occurrences: [ClassUsageOccurrence]) -> ClassUsageDTO {
        let windowTitle = "Instantiations of \(className)"
        let title = "Where is “\(className)” instantiated?"
        guard !occurrences.isEmpty else {
            let message = "No instantiations of “\(className)” found."
            return ClassUsageDTO(className: className, windowTitle: windowTitle, title: title, status: message,
                                 emptyMessage: message, sites: [], graph: nil)
        }

        // One node per site, named "File.java:line"; a repeated name on the same line gets " (n)".
        var names: Set<String> = [className]
        var locations: [String: (path: String, line: Int)] = [:]
        var callEdges: [GraphEdgeDTO] = []
        var dataEdges: [GraphEdgeDTO] = []
        var sites: [ClassUsageSiteDTO] = []
        for occurrence in occurrences {
            let base = "\(occurrence.fileURL.lastPathComponent):\(occurrence.line)"
            var unique = base
            var counter = 1
            while names.contains(unique) {
                counter += 1
                unique = "\(base) (\(counter))"
            }
            names.insert(unique)
            locations[unique] = (occurrence.fileURL.path, occurrence.line)
            // Site → class for layout ranking, class → site for the animated arrows.
            callEdges.append(GraphEdgeDTO(from: unique, to: className))
            dataEdges.append(GraphEdgeDTO(from: className, to: unique))
            sites.append(ClassUsageSiteDTO(path: occurrence.fileURL.path, line: occurrence.line, snippet: occurrence.snippet))
        }
        let nodes = names.sorted().map { name in
            GraphNodeDTO(name: name, path: locations[name]?.path, line: locations[name]?.line,
                         isOrigin: false, isGreyed: false, isOutlined: false, originColor: nil)
        }
        let diagram = DiagramGraphDTO(nodes: nodes, callEdges: callEdges, dataEdges: dataEdges,
                                      highlight: className, layoutDirection: "leftToRight",
                                      layoutSourceNodes: [], layoutCenterNode: nil, focusNodes: nil,
                                      animatedOnlyEdges: true)
        return ClassUsageDTO(className: className, windowTitle: windowTitle, title: title,
                             status: "\(occurrences.count) instantiation(s) of “\(className)” — click a node to open it",
                             emptyMessage: nil, sites: sites, graph: diagram)
    }

    // MARK: - Shared helpers

    private static func readText(_ url: URL) throws -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw KarmaServiceError.notFound("Unable to read \(url.lastPathComponent)")
        }
        return text
    }

    /// The open project's folder and the workspace generation it belongs to.
    private static func projectSnapshot() throws -> (root: URL, generation: Int) {
        let snapshot = KarmaWorkspace.shared.read { ($0.root, $0.generation) }
        guard let root = snapshot.0 else { throw KarmaServiceError.noProject }
        return (root, snapshot.1)
    }

    /// Stores a derived cache only while the project it was derived from is still open.
    private static func cache(_ generation: Int, _ update: (inout KarmaWorkspace.State) -> Void) {
        KarmaWorkspace.shared.modify { state in
            guard state.generation == generation, state.root != nil else { return }
            update(&state)
        }
    }

    /// The project tracer (`MainWindowController.variableFlowTracerCache`): the cached tracer, else one derived
    /// from the source index, else built from disk with progress. Nil when the build was cancelled.
    private static func tracer(root: URL, generation: Int, context: JobContext) -> VariableFlowTracer? {
        let cached = KarmaWorkspace.shared.read { ($0.tracer, $0.sourceIndex) }
        if let tracer = cached.0 { return tracer }
        if let index = cached.1 {
            let tracer = VariableFlowTracer(sourceIndex: index)
            cache(generation) { $0.tracer = tracer }
            return tracer
        }
        let cancellation = context.cancellationToken()
        let tracer = VariableFlowTracer(projectRoot: root, cancellation: cancellation, progress: { done, total in
            context.progress(done: done, total: total, stage: "Indexed \(done) of \(total) source files")
        })
        guard !tracer.wasCancelled, !cancellation.isCancelled else { return nil }
        cache(generation) { $0.tracer = tracer }
        return tracer
    }

    /// The project call graph (`MainWindowController.reachabilityGraphCache`), with the same three-step fallback as `tracer`.
    private static func callGraph(root: URL, generation: Int, context: JobContext) -> ProjectCallGraph? {
        let cached = KarmaWorkspace.shared.read { ($0.callGraph, $0.sourceIndex) }
        if let graph = cached.0 { return graph }
        if let index = cached.1 {
            let graph = ProjectCallGraph(sourceIndex: index)
            cache(generation) { $0.callGraph = graph }
            return graph
        }
        let cancellation = context.cancellationToken()
        let graph = ProjectCallGraph(projectRoot: root, cancellation: cancellation, progress: { done, total in
            context.progress(done: done, total: total, stage: "Indexed \(done) of \(total) source files")
        })
        guard !graph.wasCancelled, !cancellation.isCancelled else { return nil }
        cache(generation) { $0.callGraph = graph }
        return graph
    }

    /// Nodes of a graph that carry no origin, grey or outline flags and no location.
    private static func plainNodes(_ graph: CallGraph) -> [GraphNodeDTO] {
        graph.functionNames.map { name in
            GraphNodeDTO(name: name, path: nil, line: nil, isOrigin: false, isGreyed: false, isOutlined: false, originColor: nil)
        }
    }

    /// The file a backtrace frame points at inside the project (`BacktraceAnalyserWindowController.resolveFilePath`).
    private static func resolveBacktracePath(_ hint: String, root: URL) -> String? {
        let fileManager = FileManager.default
        if hint.hasPrefix("/") {
            let absolute = URL(fileURLWithPath: hint)
            if fileManager.fileExists(atPath: absolute.path) { return absolute.path }
        }
        let candidates = [
            root.appendingPathComponent(hint),
            root.appendingPathComponent((hint as NSString).lastPathComponent)
        ]
        for url in candidates where fileManager.fileExists(atPath: url.path) {
            return url.path
        }
        return nil
    }
}
