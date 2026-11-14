// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// `GET /api/events`: every `KarmaEventBus` event as a server-sent event, `event: <type>` and `data: <json>`.
/// A comment line goes out every 15 seconds so idle connections stay open.
func registerEventRoutes(_ api: RoutesBuilder) {
    api.get("events") { req async throws -> Response in
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        // A reverse proxy must not hold the events back.
        headers.replaceOrAdd(name: "X-Accel-Buffering", value: "no")

        let (stream, continuation) = AsyncStream<String>.makeStream()
        let subscription = KarmaEventBus.shared.subscribe { type, data in
            continuation.yield("event: \(type)\ndata: \(String(decoding: data, as: UTF8.self))\n\n")
        }
        let keepAlive = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                continuation.yield(": ping\n\n")
            }
        }
        continuation.onTermination = { _ in
            KarmaEventBus.shared.unsubscribe(subscription)
            keepAlive.cancel()
        }

        // `managedAsyncStream` ends the response when the closure returns and fails it when a write throws, which
        // is what happens when the browser closes the connection. The plain `asyncStream` form crashes a debug
        // build there ("Response body stream writer deinitialized before .end or .error was sent").
        let body = Response.Body(managedAsyncStream: { writer in
            defer { continuation.finish() }
            // The first chunk opens the stream in the browser before any event happens.
            try await writer.write(.buffer(ByteBuffer(string: ": connected\n\n")))
            for await chunk in stream {
                try await writer.write(.buffer(ByteBuffer(string: chunk)))
            }
        })
        return Response(status: .ok, headers: headers, body: body)
    }
}

/// `GET /api/jobs/:id` and `DELETE /api/jobs/:id` (cancel); both answer with the job as it is now.
func registerJobRoutes(_ api: RoutesBuilder) {
    api.get("jobs", ":id") { req async throws -> Response in
        let id = try jobID(req)
        guard let job = KarmaJobCenter.shared.job(id) else { throw KarmaServiceError.notFound("Unknown job \"\(id)\".") }
        return jsonResponse(job.encoded())
    }
    api.delete("jobs", ":id") { req async throws -> Response in
        let id = try jobID(req)
        guard let job = KarmaJobCenter.shared.cancel(id) else { throw KarmaServiceError.notFound("Unknown job \"\(id)\".") }
        return jsonResponse(job.encoded())
    }
}

private func jobID(_ req: Request) throws -> String {
    guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
    return id
}

/// `GET /api/fs/list?path=&files=0|1&hidden=0|1`: the folder browser behind every "choose a folder or file
/// on the server" dialog.
func registerFileSystemRoutes(_ api: RoutesBuilder) {
    api.get("fs", "list") { req async throws -> Response in
        let path = req.query[String.self, at: "path"]
        let includeFiles = req.flag("files")
        let includeHidden = req.flag("hidden")
        let listing = try await req.service {
            try FileSystemService.list(path: path, includeFiles: includeFiles, includeHidden: includeHidden)
        }
        return jsonResponse(listing)
    }
}

/// `GET /api/resources/:name`: the two pictures the web front end shows. Anything else is a 404, so the
/// route cannot be used to read other files.
func registerResourceRoutes(_ api: RoutesBuilder) {
    let allowed = ["SplashImage.jpg", "HelpSplash.jpg"]
    api.get("resources", ":name") { req async throws -> Response in
        guard let name = req.parameters.get("name"), allowed.contains(name),
              let directory = KarmaResources.directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else {
            throw Abort(.notFound, reason: "No such resource.")
        }
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "image/jpeg")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
}

/// `POST /api/app/quit`: answers, then stops the MCP listener and ends the process after 300 ms.
func registerQuitRoute(_ api: RoutesBuilder, quit: @escaping @Sendable () -> Void = defaultQuit) {
    api.post("app", "quit") { _ async throws -> Response in
        Task.detached {
            try? await Task.sleep(nanoseconds: 300_000_000)
            quit()
        }
        return okResponse()
    }
}

@Sendable
func defaultQuit() {
    KarmaMCP.stop()
    UserDefaults.standard.synchronize()
    exit(0)
}
