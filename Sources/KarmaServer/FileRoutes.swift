// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The source viewer (parity rows 5 and 13) and the line notes its gutter edits.
///
/// Offsets are UTF-16 indexes into the file text, as the viewer uses them. A route that takes an offset
/// refuses one outside the file with 400, because the engine indexes the text with it.
///
///  - `GET /api/file?path=` -> `FileService.FileDTO`.
///  - `GET /api/file/type?path=&location=` -> `{"text": String | null}`: the hover type at `location`.
///  - `GET /api/file/flow-arrows?path=` -> `FileService.FlowArrowsDTO`. The parity table also lists `&function=`,
///    but the service returns the arrows of every function in the file, so the parameter is not read.
///  - `GET /api/file/focus?path=&function=` -> `FileService.FocusDTO`, or `null` when the function has no body in
///    this file. Focus mode has no row in the parity table; this is the service's `focus` call.
///  - `GET /api/file/body-range?path=&function=` -> `{"location": Int, "length": Int}`, or `null`: the body range of
///    focus mode on its own (the table's `body-range`; the service has no separate call, so it reads the focus data).
///  - `GET /api/file/context-menu?path=&location=&selectionLocation=&selectionLength=&flowArrowsOn=&focusActive=`
///    -> `FileService.ContextMenuDTO`. The selection defaults to empty, `flowArrowsOn` to `1` and `focusActive` to `0`.
///  - `POST /api/file/resolve-call` `{path, name}` -> `FileService.DefinitionDTO`, or `null` when the index is not
///    ready or nothing defines `name`.
///  - `GET /api/definition?path=&nameOffset=` -> `FileService.DefinitionDTO`.
///  - `GET /api/file/dataflow?path=&function=` -> `FlowService.DataFlowDTO`: the source viewer's bottom pane
///    (`SourceViewer.showFunctionDataflow`), the function plus its transitive same-file callees. `graph` is null
///    when there is nothing to draw (the pane is hidden).
///  - `GET /api/notes/line?path=&line=` -> `{"text": String | null}`.
///  - `PUT /api/notes/line?path=&line=` `{text}` -> `{ok}`. Blank text removes the note.
///  - `DELETE /api/notes/line?path=&line=` -> `{ok}`.
func registerFileRoutes(_ api: RoutesBuilder) {
    struct ResolveCallRequest: Decodable {
        let path: String
        let name: String
    }
    struct NoteRequest: Decodable {
        let text: String
    }

    api.get("file") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        return jsonResponse(try await req.service { try FileService.file(path: path) })
    }
    api.get("file", "type") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        let location = try req.requiredInt("location")
        let type = try await req.service { () throws -> String? in
            try requireInside(location, length: 0, fileLength: try utf16Length(path), name: "location")
            return FileService.typeAt(path: path, location: location)
        }
        return jsonResponse(TextValue(text: type))
    }
    api.get("file", "flow-arrows") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        return jsonResponse(try await req.service { try FileService.flowArrows(path: path) })
    }
    api.get("file", "focus") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        let function = try req.requiredQuery("function")
        return optionalJSON(try await req.service { try FileService.focus(path: path, function: function) })
    }
    api.get("file", "body-range") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        let function = try req.requiredQuery("function")
        let focus = try await req.service { try FileService.focus(path: path, function: function) }
        return optionalJSON(focus.map { RangeValue(location: $0.bodyLocation, length: $0.bodyLength) })
    }
    api.get("file", "dataflow") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        let function = try req.requiredQuery("function")
        return jsonResponse(try await req.service { try FlowService.functionDataFlow(path: path, function: function) })
    }
    api.get("file", "context-menu") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        let location = try req.requiredInt("location")
        let selectionLocation = req.query[Int.self, at: "selectionLocation"] ?? 0
        let selectionLength = req.query[Int.self, at: "selectionLength"] ?? 0
        let flowArrowsOn = req.flag("flowArrowsOn", default: true)
        let focusActive = req.flag("focusActive")
        return jsonResponse(try await req.service { () throws -> FileService.ContextMenuDTO in
            let fileLength = try utf16Length(path)
            try requireInside(location, length: 0, fileLength: fileLength, name: "location")
            try requireInside(selectionLocation, length: selectionLength, fileLength: fileLength, name: "selection")
            return try FileService.contextMenu(path: path, location: location,
                                               selectionLocation: selectionLocation, selectionLength: selectionLength,
                                               flowArrowsOn: flowArrowsOn, focusActive: focusActive)
        })
    }
    api.post("file", "resolve-call") { req async throws -> Response in
        let request = try req.jsonBody(ResolveCallRequest.self)
        return optionalJSON(try await req.service { try FileService.resolveCall(path: request.path, name: request.name) })
    }
    api.get("definition") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        let nameOffset = try req.requiredInt("nameOffset")
        return jsonResponse(try await req.service { try FileService.definition(path: path, nameOffset: nameOffset) })
    }
    api.get("notes", "line") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        let line = try req.requiredInt("line")
        let text = try await req.service { try FileService.lineNote(path: path, line: line) }
        return jsonResponse(TextValue(text: text))
    }
    api.put("notes", "line") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        let line = try req.requiredInt("line")
        let request = try req.jsonBody(NoteRequest.self)
        try await req.service { try FileService.saveLineNote(path: path, line: line, text: request.text) }
        return okResponse()
    }
    api.delete("notes", "line") { req async throws -> Response in
        let path = try req.requiredQuery("path")
        let line = try req.requiredInt("line")
        try await req.service { try FileService.deleteLineNote(path: path, line: line) }
        return okResponse()
    }
}

/// `{"text": <string or null>}`. A nil value is sent as `null`, not left out.
private struct TextValue: Encodable {
    let text: String?

    private enum CodingKeys: String, CodingKey {
        case text
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
    }
}

/// `{"location": Int, "length": Int}`: a UTF-16 range.
private struct RangeValue: Encodable {
    let location: Int
    let length: Int
}

/// The DTO as JSON, or the literal `null` when there is none.
private func optionalJSON<T: Encodable>(_ value: T?) -> Response {
    guard let value else {
        return textResponse("null", contentType: "application/json; charset=utf-8")
    }
    return jsonResponse(value)
}

/// The UTF-16 length of a source file, read the way the viewer reads it.
private func utf16Length(_ path: String) throws -> Int {
    guard let text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
        throw KarmaServiceError.invalid("Could not read file:\n\(path)")
    }
    return (text as NSString).length
}

/// Refuses a UTF-16 range that is negative or reaches past the end of a file of `fileLength` units.
/// The engine indexes the text with these offsets, so an out-of-range value must not get that far.
private func requireInside(_ location: Int, length: Int, fileLength: Int, name: String) throws {
    guard location >= 0, length >= 0, location <= fileLength, length <= fileLength - location else {
        throw Abort(.badRequest, reason: "The \"\(name)\" range is outside the file.")
    }
}
