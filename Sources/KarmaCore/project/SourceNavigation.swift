// by cipher.org.uk
import Foundation

/// Describes one control-flow arrow overlaid on the source: an edge of the
/// parsed CFG mapped to source lines. Stored in line numbers; a front end
/// resolves them to coordinates when drawing.
struct FlowArrow: Hashable {
    enum Kind: String, Codable {
        case branchTrue    // decision T → branch body
        case branchFalse   // decision F → else / skip-to-continuation / loop exit
        case loopBack      // loop body end → loop header (upward)
        case rejoin        // branch/block end → continuation (merge)
        case flow          // plain statement-to-statement sequential flow
        case exit          // return/break/continue/goto marker
    }
    let fromLine: Int
    let toLine: Int
    let kind: Kind
}

/// What a source viewer needs to know about a file's code, independent of how
/// it is drawn: which names are clickable (function definitions, classes, call
/// sites), what the word under a click is, where a function's body is, and the
/// control-flow arrows. Shared by the AppKit `SourceViewer` and the web front
/// end. All ranges are UTF-16 (`NSRange`) offsets into the source.
enum SourceNavigation {
    typealias NamedRange = (name: String, range: NSRange)

    // MARK: - Clickable names

    /// The function definition name ranges and, for Java/C#, the class name
    /// ranges of `source`. Empty for languages the diagram engine does not know.
    static func clickableRanges(source: String, fileExtension ext: String)
        -> (functions: [NamedRange], classes: [NamedRange]) {
        guard DiagramLanguage.from(ext: ext) != nil else { return ([], []) }
        let lowerExt = ext.lowercased()

        let defs = diagramDefinitions(source: source, ext: ext)
        let classNames = CCFunctionParser(source: source).parseClassNames()

        var functions: [NamedRange] = []
        for def in defs {
            guard def.nameRange.location != NSNotFound, def.nameRange.length > 0 else { continue }
            functions.append((name: def.name, range: def.nameRange))
        }

        var classes: [NamedRange] = []
        if lowerExt == "java" || lowerExt == "cs" || lowerExt == "csx" {
            for cls in classNames {
                let r = cls.range
                guard r.location != NSNotFound, r.length > 0 else { continue }
                classes.append((name: cls.name, range: r))
            }
        }
        return (functions, classes)
    }

    /// Every call site of a name for which `isKnownName` is true: an identifier
    /// followed (after optional whitespace) by `(`, that is not itself a
    /// definition name in this file (`definitionRanges`) and not a keyword.
    static func callSites(source: String,
                          definitionRanges: [NamedRange],
                          isKnownName: (String) -> Bool) -> [NamedRange] {
        // Character ranges that must NOT become call sites: the function/class
        // definition sites in this file.
        var excluded = Set<Int>()
        for entry in definitionRanges {
            let range = entry.range
            for i in range.location..<(range.location + range.length) {
                excluded.insert(i)
            }
        }

        let ns = source as NSString
        let len = ns.length
        var callSites: [NamedRange] = []

        var i = 0
        while i < len {
            let c = ns.character(at: i)
            guard isCallIdentStart(c) else { i += 1; continue }
            let start = i
            i += 1
            while i < len && isCallIdentChar(ns.character(at: i)) { i += 1 }
            let ident = ns.substring(with: NSRange(location: start, length: i - start))

            // Skip control-flow / declaration keywords entirely.
            if isCallKeyword(ident) || ident.isEmpty { continue }

            // The token is a candidate call site only if a `(` (possibly after
            // whitespace) follows, we're not inside a definition name, the name
            // is defined somewhere in the project, and it is not the current
            // file's own definition name range.
            var j = i
            while j < len && isCallWs(ns.character(at: j)) { j += 1 }
            guard j < len, ns.character(at: j) == 0x28 else { continue }

            let nameOffset = start
            var isInsideDefinition = false
            for k in nameOffset..<i where excluded.contains(k) { isInsideDefinition = true; break }
            guard isInsideDefinition == false else { continue }

            // Only names that resolve to a definition in the open project.
            guard isKnownName(ident) else { continue }

            let range = NSRange(location: start, length: i - start)
            callSites.append((name: ident, range: range))

            i = j + 1
        }
        return callSites
    }

    private static func isCallIdentStart(_ scalar: unichar) -> Bool {
        return (scalar >= 0x41 && scalar <= 0x5A) || scalar == 0x5F || (scalar >= 0x61 && scalar <= 0x7A)
    }

    private static func isCallIdentChar(_ scalar: unichar) -> Bool {
        return isCallIdentStart(scalar) || (scalar >= 0x30 && scalar <= 0x39)
    }

    private static func isCallWs(_ scalar: unichar) -> Bool {
        return scalar == 0x20 || scalar == 0x09 || scalar == 0x0A || scalar == 0x0D
    }

    /// Control-flow / declaration keywords and punctuation-like names that
    /// should never be treated as call sites even when immediately followed by
    /// `(`.
    private static func isCallKeyword(_ ident: String) -> Bool {
        switch ident {
        case "if", "for", "while", "switch", "catch", "return", "throw", "new",
             "import", "export", "from", "use", "as", "in", "of", "sizeof",
             "guard", "do", "else", "case", "default", "try", "finally",
             "instanceof", "typeof", "yield", "await", "assert", "defer",
             "struct", "union", "enum", "class", "interface", "protocol",
             "extension", "func", "function", "def", "let", "var", "const",
             "public", "private", "internal", "protected", "static", "final",
             "override", "typealias", "typedef", "template", "namespace",
             "using", "require", "include", "define", "supers", "match",
             "when", "where", "impl", "trait", "self", "super", "this",
             "init", "int", "float", "double", "long", "short", "char",
             "void", "bool", "boolean", "byte", "string", "String", "size_t":
            return true
        default:
            return false
        }
    }

    // MARK: - Lookups

    static func functionName(at charIndex: Int, in functionRanges: [NamedRange]) -> String? {
        guard charIndex >= 0 else { return nil }
        for entry in functionRanges where NSLocationInRange(charIndex, entry.range) {
            return entry.name
        }
        return nil
    }

    /// The text of the first function named `functionName` in `functionRanges`
    /// (the whole `source` when it is not found).
    static func extractSnippet(for functionName: String, in source: String, functionRanges: [NamedRange]) -> String {
        for entry in functionRanges where entry.name == functionName {
            let ns = source as NSString
            if entry.range.location != NSNotFound, entry.range.location + entry.range.length <= ns.length {
                return ns.substring(with: entry.range)
            }
        }
        return source
    }

    /// Locates the full body range of `functionName` in `source`, so a focused
    /// region spans signature + body (the whole readable unit), not just the name.
    static func bodyRange(for functionName: String, source: String, fileExtension ext: String) -> NSRange? {
        let defs = diagramDefinitions(source: source, ext: ext)
        guard let def = defs.first(where: { $0.name == functionName }) else { return nil }
        let r = def.bodyRange
        guard r.location != NSNotFound, r.length > 0 else { return nil }
        return r
    }

    /// The identifier word under/around `charIndex` (also straddling an active
    /// `selection`), or nil when it is empty or a language keyword — used to
    /// offer the "Follow the variable" context-menu action.
    static func variableWord(at charIndex: Int, in source: String, selection: NSRange) -> String? {
        let ns = source as NSString
        guard ns.length > 0 else { return nil }

        // Prefer a currently-highlighted selection of a single word.
        if selection.location != NSNotFound, selection.length > 0, selection.length <= 80,
           let selected = ns.substring(with: selection) as String? {
            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.allSatisfy({ isVariableWordChar($0) }), !trimmed.isEmpty {
                return isVariableKeyword(trimmed) ? nil : trimmed
            }
        }

        let idx = min(max(charIndex, 0), ns.length)
        var start = idx
        var end = idx
        while start > 0 && ns.character(at: start - 1) != 0x0A {
            let c = ns.character(at: start - 1)
            if isVariableWordScalar(c) { start -= 1 } else { break }
        }
        while end < ns.length {
            let c = ns.character(at: end)
            if isVariableWordScalar(c) { end += 1 } else { break }
        }
        guard end > start else { return nil }
        let word = ns.substring(with: NSRange(location: start, length: end - start))
        guard !word.isEmpty, !isVariableKeyword(word) else { return nil }
        return word
    }

    private static func isVariableWordChar(_ c: Character) -> Bool {
        if c.isASCII, let v = c.asciiValue {
            return isVariableWordScalar(UInt16(v))
        }
        return c.isLetter || c == "_"
    }

    private static func isVariableWordScalar(_ c: unichar) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x5F
    }

    private static func isVariableKeyword(_ ident: String) -> Bool {
        switch ident {
        case "if", "for", "while", "switch", "catch", "return", "throw", "new",
             "import", "export", "from", "use", "as", "in", "of", "sizeof",
             "guard", "do", "else", "case", "default", "try", "finally",
             "instanceof", "typeof", "yield", "await", "assert", "defer",
             "struct", "union", "enum", "class", "interface", "protocol",
             "extension", "func", "function", "def", "let", "var", "const",
             "public", "private", "internal", "protected", "static", "final",
             "override", "typealias", "typedef", "template", "namespace",
             "using", "require", "include", "define", "match", "when", "where",
             "impl", "trait", "self", "super", "this", "init",
             "int", "float", "double", "long", "short", "char", "void", "bool",
             "boolean", "byte", "string", "String", "size_t", "null", "nil",
             "None", "true", "false", "NULL", "nullptr", "undefined", "NaN":
            return true
        default:
            return false
        }
    }

    // MARK: - Flow arrows

    /// Builds the control-flow arrows for every function defined in `source`
    /// (C/C++/ObjC, Java, C#, Kotlin, Go, Rust, Python, Ruby, JS/TS), with the
    /// offset of each logical line's start. The arrows are empty for
    /// unsupported languages or files with no parseable flows.
    static func flowArrows(for source: String, fileExtension ext: String) -> (arrows: [FlowArrow], lineStarts: [Int]) {
        let lineStarts = flowLineStarts(in: source)
        guard DiagramLanguage.from(ext: ext) != nil else {
            return ([], lineStarts)
        }
        let defs = diagramDefinitions(source: source, ext: ext)
        var arrows: [FlowArrow] = []
        var seen: Set<FlowArrow> = []
        for def in defs {
            guard let flow = ControlFlowParser.analyze(source: source, ext: ext, functionName: def.name, definition: def) else { continue }
            for arrow in controlFlowArrows(from: flow) where seen.insert(arrow).inserted {
                arrows.append(arrow)
            }
        }
        // Drop arrows referencing lines outside the document.
        let lineCount = lineStarts.count
        let kept = arrows.filter { $0.fromLine <= lineCount && $0.toLine <= lineCount && $0.fromLine >= 1 && $0.toLine >= 1 }
        return (kept, lineStarts)
    }

    /// Character offset of each logical line's start (index N → line N+1).
    static func flowLineStarts(in source: String) -> [Int] {
        var starts: [Int] = [0]
        var index = 0
        for unit in source.utf16 {
            index += 1
            if unit == 0x0A { starts.append(index) }
        }
        return starts
    }

    /// Converts one control-flow graph into overlay arrows. Walks **every edge**
    /// of the parsed CFG (mirroring how the flow diagram draws them) so a flow is
    /// traced statement→statement through a whole branch body, then on into the
    /// join/continuation — not just a single decision-to-landing hop. Kinds, from
    /// the parser's structured edges: decision T/F fan-out, loop back-edges,
    /// merge (rejoin), plain sequential flow, and terminator (exit) markers.
    static func controlFlowArrows(from flow: ControlFlowParser) -> [FlowArrow] {
        var arrows: [FlowArrow] = []
        let nodes = flow.nodes
        let nodeById = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        for edge in flow.edges {
            guard let fromNode = nodeById[edge.from],
                  let fromLine = fromNode.sourceLine else { continue }
            // A terminator node gets a marker chevron (kind .exit) instead of a
            // continuation arrow — execution does not flow out of it.
            if case let .block(text) = fromNode.kind, isExitStatement(text) { continue }

            // Target line: the node's own line, or (for join/exit nodes without a
            // line) the first real line reachable from it — the continuation.
            var toLine = nodeById[edge.to]?.sourceLine
            if toLine == nil {
                toLine = resolvedLine(for: edge.to, in: flow)
            }
            guard let tl = toLine, tl != fromLine else { continue }

            let kind: FlowArrow.Kind
            if edge.isBackEdge {
                kind = .loopBack
            } else if isDecisionNode(fromNode) && edge.branch == "T" {
                kind = .branchTrue
            } else if isDecisionNode(fromNode) && edge.branch == "F" {
                kind = .branchFalse
            } else if nodeById[edge.to].map({ isJoinNode($0) }) == true {
                kind = .rejoin   // block end merging into the continuation
            } else {
                kind = .flow     // sequential statement→statement flow
            }
            arrows.append(FlowArrow(fromLine: fromLine, toLine: tl, kind: kind))
        }

        // Exit markers: return/break/continue/goto/throw and, for Swift/Rust, any
        // statement node flagged as exiting in the parsed body.
        for node in nodes {
            guard case let .block(text) = node.kind else { continue }
            if isExitStatement(text), let l = node.sourceLine {
                arrows.append(FlowArrow(fromLine: l, toLine: l, kind: .exit))
            }
        }

        return arrows
    }

    /// The nearest source line reachable from `id`'s outgoing non-back edge —
    /// resolves joins to the line execution resumes after the merge.
    private static func resolvedLine(for id: Int, in flow: ControlFlowParser) -> Int? {
        let nodeById = Dictionary(uniqueKeysWithValues: flow.nodes.map { ($0.id, $0) })
        var current = id
        var hops = 0
        while hops < flow.nodes.count {
            hops += 1
            guard let node = nodeById[current] else { return nil }
            if let l = node.sourceLine { return l }
            guard let next = flow.edges.first(where: { $0.from == current && !$0.isBackEdge }) else { return nil }
            current = next.to
        }
        return nil
    }

    private static func isDecisionNode(_ node: ControlFlowParser.Node) -> Bool {
        switch node.kind {
        case .decision, .switchCase: return true
        default: return false
        }
    }

    private static func isJoinNode(_ node: ControlFlowParser.Node) -> Bool {
        if case .join = node.kind { return true }
        return false
    }

    private static func isExitStatement(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let first = trimmed.split(whereSeparator: { $0 == " " || $0 == "(" || $0 == ";" }).first else {
            return false
        }
        return first == "return" || first == "break" ||
            first == "continue" || first == "goto" ||
            first == "throw" || first == "exit"
    }
}
