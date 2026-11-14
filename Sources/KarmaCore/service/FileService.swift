// by cipher.org.uk
import Foundation

/// What the source viewer shows for one file and the actions it offers on it:
/// highlighted text with clickable names and call sites, hover types, flow
/// arrows, focus-mode chips, the context menu, definitions, the note gutter and
/// the ML highlights. Ports `SourceViewer`, `HighlightedLinesViewController`,
/// `NotePopoverController` and `DefinitionWindowController`. Drawing stays in
/// the front end; every offset is a UTF-16 index into the file text.
public enum FileService {

    // MARK: - Data transfer objects

    /// One coloured span of the file. `kind` is a `SyntaxTokenKind` raw value.
    public struct TokenDTO: Codable, Sendable {
        public var location: Int
        public var length: Int
        public var kind: String

        public init(location: Int, length: Int, kind: String) {
            self.location = location
            self.length = length
            self.kind = kind
        }
    }

    /// A clickable name (function, class or call site) and its UTF-16 range.
    public struct NamedRangeDTO: Codable, Sendable {
        public var name: String
        public var location: Int
        public var length: Int

        public init(name: String, location: Int, length: Int) {
            self.name = name
            self.location = location
            self.length = length
        }
    }

    /// A line the ML scan flagged, with the line's text as the highlighted-lines table previews it.
    public struct MLLineDTO: Codable, Sendable {
        public var line: Int
        public var probability: Double
        public var text: String

        public init(line: Int, probability: Double, text: String) {
            self.line = line
            self.probability = probability
            self.text = text
        }
    }

    /// `GET /api/file?path=`: everything the viewer needs to show a file.
    public struct FileDTO: Codable, Sendable {
        public var path: String
        public var text: String
        /// The path extension, lowercased.
        public var ext: String
        /// Empty when the extension has no highlighting.
        public var tokens: [TokenDTO]
        /// Function definition names (empty for languages without clickable names).
        public var functionRanges: [NamedRangeDTO]
        /// Java/C# class names.
        public var classRanges: [NamedRangeDTO]
        /// Calls of project-defined functions. Empty until the project index is ready.
        public var callSites: [NamedRangeDTO]
        /// 1-based lines that carry a saved note, ascending.
        public var noteLines: [Int]
        /// High-risk lines from the last ML scan, ascending by line.
        public var mlLines: [MLLineDTO]

        public init(path: String, text: String, ext: String, tokens: [TokenDTO],
                    functionRanges: [NamedRangeDTO], classRanges: [NamedRangeDTO], callSites: [NamedRangeDTO],
                    noteLines: [Int], mlLines: [MLLineDTO]) {
            self.path = path
            self.text = text
            self.ext = ext
            self.tokens = tokens
            self.functionRanges = functionRanges
            self.classRanges = classRanges
            self.callSites = callSites
            self.noteLines = noteLines
            self.mlLines = mlLines
        }
    }

    /// One control-flow arrow. `kind` is a `FlowArrow.Kind` raw value.
    public struct FlowArrowDTO: Codable, Sendable {
        public var fromLine: Int
        public var toLine: Int
        public var kind: String

        public init(fromLine: Int, toLine: Int, kind: String) {
            self.fromLine = fromLine
            self.toLine = toLine
            self.kind = kind
        }
    }

    /// `GET /api/file/flow-arrows?path=`: the arrows, and the UTF-16 offset of each line's start (index N = line N+1).
    public struct FlowArrowsDTO: Codable, Sendable {
        public var arrows: [FlowArrowDTO]
        public var lineStarts: [Int]

        public init(arrows: [FlowArrowDTO], lineStarts: [Int]) {
            self.arrows = arrows
            self.lineStarts = lineStarts
        }
    }

    /// A caller or callee chip of focus mode: the function's name and the file that defines it.
    public struct FocusChipDTO: Codable, Sendable {
        public var name: String
        public var path: String

        public init(name: String, path: String) {
            self.name = name
            self.path = path
        }
    }

    /// Focus mode for one function: the body stays sharp, the rest is dimmed, and the chip bars
    /// list the direct callers (above) and callees (below). A bar is shown only when its list is not empty.
    public struct FocusDTO: Codable, Sendable {
        public var function: String
        /// UTF-16 range of the signature and body, the part that stays sharp.
        public var bodyLocation: Int
        public var bodyLength: Int
        public var callers: [FocusChipDTO]
        public var callees: [FocusChipDTO]

        public init(function: String, bodyLocation: Int, bodyLength: Int,
                    callers: [FocusChipDTO], callees: [FocusChipDTO]) {
            self.function = function
            self.bodyLocation = bodyLocation
            self.bodyLength = bodyLength
            self.callers = callers
            self.callees = callees
        }
    }

    /// The facts `SourceViewer.textView(_:menu:for:at:)` decides the menu from. The items appear in this order:
    /// Copy; the flow arrows toggle; "Focus on"/"Exit Focus Mode"; Complexity distribution; then, when
    /// `functionName` is set, Show Flow Diagram, Simulate and Show reachability; then, when `variableName` is
    /// set, Follow the variable; then Backtrace Analyser, Find external entries and (AI) How to fix it.
    public struct ContextMenuDTO: Codable, Sendable {
        /// Copy is enabled when something is selected or the file is not empty.
        public var copyEnabled: Bool
        /// "Hide Flow Arrows on Code" while arrows are on, otherwise "Show Flow Arrows on Code".
        public var flowArrowsTitle: String
        public var flowArrowsOn: Bool
        /// True while focus mode is on, which adds "Exit Focus Mode" (Esc).
        public var exitFocusAvailable: Bool
        /// The function whose name is under the pointer. Drives "Focus on", "Show Flow Diagram for",
        /// "Simulate" and "Show reachability of". Nil when the pointer is not on a clickable function name.
        public var functionName: String?
        /// True when the file's language has flow diagrams (the only languages with clickable function names).
        public var flowDiagramSupported: Bool
        /// The identifier under the pointer or in the selection, for "Follow the variable". Nil when none.
        public var variableName: String?
        /// The UTF-16 offset "Follow the variable" traces from: the selection start when the pointer is inside
        /// a non-empty selection, otherwise the pointer offset.
        public var variableFlowLocation: Int
        /// The 1-based line under the pointer and its text, the arguments of "(AI) How to fix it".
        public var lineNumber: Int
        public var lineText: String

        public init(copyEnabled: Bool, flowArrowsTitle: String, flowArrowsOn: Bool, exitFocusAvailable: Bool,
                    functionName: String?, flowDiagramSupported: Bool, variableName: String?,
                    variableFlowLocation: Int, lineNumber: Int, lineText: String) {
            self.copyEnabled = copyEnabled
            self.flowArrowsTitle = flowArrowsTitle
            self.flowArrowsOn = flowArrowsOn
            self.exitFocusAvailable = exitFocusAvailable
            self.functionName = functionName
            self.flowDiagramSupported = flowDiagramSupported
            self.variableName = variableName
            self.variableFlowLocation = variableFlowLocation
            self.lineNumber = lineNumber
            self.lineText = lineText
        }
    }

    /// A definition: the whole file text (the popup shows it with the definition line scrolled to), the
    /// 1-based line of the definition name, and the name itself.
    public struct DefinitionDTO: Codable, Sendable {
        public var path: String
        public var text: String
        public var line: Int
        public var name: String

        public init(path: String, text: String, line: Int, name: String) {
            self.path = path
            self.text = text
            self.line = line
            self.name = name
        }
    }

    // MARK: - File

    /// `GET /api/file?path=`: the file as `SourceViewer.display(fileAt:)` shows it.
    /// Throws `KarmaServiceError.invalid` with the viewer's "Could not read file" text when the file cannot be read.
    public static func file(path: String) throws -> FileDTO {
        let text = try readSource(path)
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        let tokens = SyntaxTokenizer.shared.tokens(for: text, fileExtension: ext)?.map {
            TokenDTO(location: $0.range.location, length: $0.range.length, kind: $0.kind.rawValue)
        } ?? []
        let names = clickableNames(text: text, ext: ext)
        let callSites = callSiteRanges(text: text, ext: ext, definitions: names.functions + names.classes)
        return FileDTO(path: path,
                       text: text,
                       ext: ext.lowercased(),
                       tokens: tokens,
                       functionRanges: names.functions.map(namedDTO),
                       classRanges: names.classes.map(namedDTO),
                       callSites: callSites.map(namedDTO),
                       noteLines: NoteStore.shared.lineNumbers(for: url).sorted(),
                       mlLines: mlLines(path: path, text: text))
    }

    /// `GET /api/file/type?path=&location=`: the hover tooltip text for the identifier at `location`. Nil when
    /// the language has no type resolution (only C, C++, Java and C# have it) or nothing is known.
    public static func typeAt(path: String, location: Int) -> String? {
        guard let languageName = typeLanguageName(forExtension: URL(fileURLWithPath: path).pathExtension.lowercased()),
              let text = try? readSource(path) else { return nil }
        let language = Language(name: languageName, extensions: [])
        guard let type = TypeResolver.type(at: location, in: text, language: language), !type.isEmpty else { return nil }
        return type
    }

    /// `GET /api/file/flow-arrows?path=`: the control-flow arrows of every function in the file.
    public static func flowArrows(path: String) throws -> FlowArrowsDTO {
        let text = try readSource(path)
        let result = SourceNavigation.flowArrows(for: text, fileExtension: URL(fileURLWithPath: path).pathExtension)
        return FlowArrowsDTO(arrows: result.arrows.map {
            FlowArrowDTO(fromLine: $0.fromLine, toLine: $0.toLine, kind: $0.kind.rawValue)
        }, lineStarts: result.lineStarts)
    }

    /// The focus data for `function`: its body range and the chips of `SourceViewer.setFocusMode(functionName:)`.
    /// Nil when the function has no body in this file, in which case the viewer does not enter focus mode.
    public static func focus(path: String, function: String) throws -> FocusDTO? {
        let text = try readSource(path)
        let url = URL(fileURLWithPath: path)
        guard let body = SourceNavigation.bodyRange(for: function, source: text, fileExtension: url.pathExtension) else {
            return nil
        }
        let chips = tunnel(fileURL: url, function: function)
        return FocusDTO(function: function, bodyLocation: body.location, bodyLength: body.length,
                        callers: chips.callers, callees: chips.callees)
    }

    /// The facts behind the viewer's right-click menu for a click at `location` with the given selection.
    /// `flowArrowsOn` and `focusActive` are the viewer's own toggles, which the front end keeps.
    public static func contextMenu(path: String, location: Int, selectionLocation: Int, selectionLength: Int,
                                   flowArrowsOn: Bool = true, focusActive: Bool = false) throws -> ContextMenuDTO {
        let text = try readSource(path)
        let ext = URL(fileURLWithPath: path).pathExtension
        let ns = text as NSString
        let selection = NSRange(location: selectionLocation, length: selectionLength)

        let functionName = SourceNavigation.functionName(at: location, in: clickableNames(text: text, ext: ext).functions)
        let variableName = SourceNavigation.variableWord(at: location, in: text, selection: selection)

        // The clicked line, as "(AI) How to fix it" sends it.
        let charIndex = min(max(location, 0), ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
        let lineText = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        var newlines = 0
        for index in 0..<lineRange.location where ns.character(at: index) == 0x0A { newlines += 1 }

        // "Follow the variable" anchors at the selection start when the pointer is inside a selection.
        let variableFlowLocation = selectionLength > 0 && NSLocationInRange(location, selection)
            ? selectionLocation
            : location

        return ContextMenuDTO(
            copyEnabled: selectionLength > 0 || !text.isEmpty,
            flowArrowsTitle: flowArrowsOn ? "Hide Flow Arrows on Code" : "Show Flow Arrows on Code",
            flowArrowsOn: flowArrowsOn,
            exitFocusAvailable: focusActive,
            functionName: functionName,
            flowDiagramSupported: DiagramLanguage.from(ext: ext) != nil,
            variableName: variableName,
            variableFlowLocation: variableFlowLocation,
            lineNumber: newlines + 1,
            lineText: lineText)
    }

    /// The identifier under the pointer or in the selection (`SourceNavigation.variableWord`), or nil.
    public static func variableWord(path: String, location: Int, selectionLocation: Int, selectionLength: Int) throws -> String? {
        let text = try readSource(path)
        return SourceNavigation.variableWord(at: location, in: text,
                                             selection: NSRange(location: selectionLocation, length: selectionLength))
    }

    // MARK: - Definitions

    /// Click on a call site (`SourceViewer.handleCallSiteClick`): the definition the index resolves `name` to,
    /// preferring one in `path`. Nil when the project index is not ready or nothing defines `name`.
    public static func resolveCall(path: String, name: String) throws -> DefinitionDTO? {
        guard let index = KarmaWorkspace.shared.read({ $0.definitionIndex }),
              let location = index.lookUp(name: name, preferredFileURL: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try definition(path: location.fileURL.path, nameOffset: location.nameOffset)
    }

    /// The text `DefinitionWindowController` shows for a definition whose name starts at `nameOffset`.
    /// Throws `KarmaServiceError.invalid("Unable to read the definition file.")`, the window's own text, when unreadable.
    public static func definition(path: String, nameOffset: Int) throws -> DefinitionDTO {
        guard let source = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            throw KarmaServiceError.invalid("Unable to read the definition file.")
        }
        let ns = source as NSString
        let offset = min(max(nameOffset, 0), ns.length)
        // Same as the window: the number of lines before the offset, plus one.
        let line = ns.substring(to: offset).components(separatedBy: "\n").count
        return DefinitionDTO(path: path, text: source, line: line, name: identifier(at: offset, in: ns))
    }

    // MARK: - Line notes

    /// The note on `line` (1-based) of the file, or nil. Notes are keyed by the absolute file path, as the viewer keys them.
    public static func lineNote(path: String, line: Int) throws -> String? {
        _ = try KarmaWorkspace.shared.requireRoot()
        return NoteStore.shared.note(for: URL(fileURLWithPath: path), line: line)
    }

    /// Saves the note on `line`. Blank text removes the note, as the note popover's Save does with an empty field.
    public static func saveLineNote(path: String, line: Int, text: String) throws {
        _ = try KarmaWorkspace.shared.requireRoot()
        try requireLine(line)
        if NoteStore.shared.setNote(for: URL(fileURLWithPath: path), line: line, text: text) {
            KarmaEventBus.shared.post("notes.changed")
        }
    }

    /// Removes the note on `line`, as the note popover's Remove does.
    public static func deleteLineNote(path: String, line: Int) throws {
        _ = try KarmaWorkspace.shared.requireRoot()
        try requireLine(line)
        if NoteStore.shared.setNote(for: URL(fileURLWithPath: path), line: line, text: nil) {
            KarmaEventBus.shared.post("notes.changed")
        }
    }

    // MARK: - Private helpers

    /// The file text as `SourceViewer.display(fileAt:)` reads it: UTF-8, no size limit.
    private static func readSource(_ path: String) throws -> String {
        guard let text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            throw KarmaServiceError.invalid("Could not read file:\n\(path)")
        }
        return text
    }

    /// Function and class names the viewer makes clickable. Like the viewer, nothing is clickable for a
    /// language without flow diagrams.
    private static func clickableNames(text: String, ext: String)
        -> (functions: [SourceNavigation.NamedRange], classes: [SourceNavigation.NamedRange]) {
        guard DiagramLanguage.from(ext: ext) != nil else { return ([], []) }
        return SourceNavigation.clickableRanges(source: text, fileExtension: ext)
    }

    /// Call sites of project-defined names. Like the viewer, none are marked before the project index exists.
    private static func callSiteRanges(text: String, ext: String,
                                       definitions: [SourceNavigation.NamedRange]) -> [SourceNavigation.NamedRange] {
        guard DiagramLanguage.from(ext: ext) != nil,
              let index = KarmaWorkspace.shared.read({ $0.definitionIndex }) else { return [] }
        return SourceNavigation.callSites(source: text, definitionRanges: definitions,
                                          isKnownName: { index.contains(name: $0) })
    }

    private static func namedDTO(_ entry: SourceNavigation.NamedRange) -> NamedRangeDTO {
        NamedRangeDTO(name: entry.name, location: entry.range.location, length: entry.range.length)
    }

    /// The hover-type languages `SourceViewer.configureTypeTooltip(forExtension:)` enables.
    private static func typeLanguageName(forExtension ext: String) -> String? {
        switch ext {
        case "c", "h": return "C"
        case "cpp", "cc", "cxx", "hpp", "hxx", "hh": return "C++"
        case "java": return "Java"
        case "cs", "csx": return "C#"
        default: return nil
        }
    }

    /// The high-risk lines of the last scan, with their text as `HighlightedLinesViewController` previews it.
    private static func mlLines(path: String, text: String) -> [MLLineDTO] {
        let lines = MLScanResultStore.shared.highRiskLines(forFile: path)
        let ns = text as NSString
        let starts = SourceNavigation.flowLineStarts(in: text)
        return lines.sorted { $0.key < $1.key }.map {
            MLLineDTO(line: $0.key, probability: $0.value, text: previewText(line: $0.key, starts: starts, ns: ns))
        }
    }

    /// The text of `line` (1-based) up to its newline, trimmed of spaces and tabs.
    private static func previewText(line: Int, starts: [Int], ns: NSString) -> String {
        guard line >= 1, line <= starts.count else { return "" }
        let start = starts[line - 1]
        var end = start
        while end < ns.length && ns.character(at: end) != 0x0A { end += 1 }
        guard end > start else { return "" }
        return ns.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespaces)
    }

    /// The focus chips: the callers of `function` and the functions its body calls, from the project call graph.
    /// The definition is the one in `fileURL` when there is one, otherwise the first of that name.
    private static func tunnel(fileURL: URL, function: String) -> (callers: [FocusChipDTO], callees: [FocusChipDTO]) {
        guard let graph = KarmaWorkspace.shared.read({ $0.callGraph }) else { return ([], []) }
        let standardized = fileURL.standardizedFileURL
        let ref = graph.byName[function]?.first(where: { $0.fileURL == standardized }) ?? graph.byName[function]?.first

        // The caller set is unordered; sort it so the chips keep the same order between requests.
        let callers = (graph.callers[function] ?? [])
            .sorted { ($0.fileURL.path, $0.name) < ($1.fileURL.path, $1.name) }
            .map { FocusChipDTO(name: $0.name, path: $0.fileURL.path) }

        var callees: [FocusChipDTO] = []
        if let ref {
            for edge in graph.callees[ref] ?? [] {
                for target in graph.byName[edge.calleeName] ?? [] {
                    callees.append(FocusChipDTO(name: target.name, path: target.fileURL.path))
                }
            }
        }
        return (callers, callees)
    }

    /// The identifier that starts at `offset` (letters, digits and underscores), or "" when none does.
    private static func identifier(at offset: Int, in ns: NSString) -> String {
        var end = offset
        while end < ns.length && isIdentifierUnit(ns.character(at: end)) { end += 1 }
        guard end > offset else { return "" }
        return ns.substring(with: NSRange(location: offset, length: end - offset))
    }

    private static func isIdentifierUnit(_ c: unichar) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
    }

    private static func requireLine(_ line: Int) throws {
        guard line >= 1 else { throw KarmaServiceError.invalid("Line numbers start at 1.") }
    }
}
