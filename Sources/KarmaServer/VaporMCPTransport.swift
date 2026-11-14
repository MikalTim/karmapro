// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The MCP listener for the web server, built on Vapor. Like `MCPHTTPServer` in
/// the AppKit app, it runs beside the web UI on its own loopback application,
/// so the MCP endpoint does not depend on the UI server's routes.
final class VaporMCPTransport: MCPTransport {
    /// Handlers may block, so they run off the event loop and answer through the callback.
    var handler: ((MCPHTTPRequest, @escaping (MCPHTTPResponse) -> Void) -> Void)?
    /// Called for a GET that asks for `text/event-stream`. Return false to refuse
    /// the stream; the peer then gets a plain 401.
    var onStream: ((MCPHTTPRequest, MCPEventStream) -> Bool)?
    var log: ((String) -> Void)?
    /// Seconds between comment frames on an event stream. Clients ignore comment
    /// frames, but a frame that cannot be written shows that the client has gone,
    /// and the stream then closes.
    var heartbeatInterval: TimeInterval = 15

    private static let host = "127.0.0.1"
    private let lock = NSLock()
    private var application: Application?
    private var streams: [VaporMCPEventStream] = []

    deinit {
        stop()
    }

    func start(port: UInt16) throws -> UInt16 {
        stop()
        // Vapor's start-up is async; this thread waits for it to listen or fail.
        let outcome = StartOutcome()
        let ready = DispatchSemaphore(value: 0)
        Task {
            do {
                outcome.result = .success(try await self.bind(port: port))
            } catch {
                outcome.result = .failure(error)
            }
            ready.signal()
        }
        ready.wait()
        let (app, bound) = try outcome.result!.get()
        lock.lock()
        application = app
        lock.unlock()
        return bound
    }

    func stop() {
        lock.lock()
        let app = application
        application = nil
        let open = streams
        streams = []
        lock.unlock()
        open.forEach { $0.close() }
        guard let app else { return }
        let finished = DispatchSemaphore(value: 0)
        Task {
            await app.http.server.shared.shutdown()
            try? await app.asyncShutdown()
            finished.signal()
        }
        finished.wait()
    }

    // MARK: - Listener

    private func bind(port: UInt16) async throws -> (Application, UInt16) {
        let app = try await Application.make(Environment(name: "production", arguments: ["karma"]))
        do {
            app.http.server.configuration.hostname = Self.host
            app.http.server.configuration.port = Int(port)
            app.routes.defaultMaxBodySize = "16mb"
            registerCatchAll(on: app)
            try await app.asyncBoot()
            let server = app.http.server.shared
            try await server.start(address: .hostname(Self.host, port: Int(port)))
            guard let bound = server.localAddress?.port else {
                throw NSError(domain: "MCP", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "The listener did not report its port."])
            }
            return (app, UInt16(bound))
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
    }

    private func registerCatchAll(on app: Application) {
        let methods: [HTTPMethod] = [.GET, .POST, .DELETE]
        for method in methods {
            // `**` matches only paths below the root, so the root path is registered on its own.
            app.on(method) { [weak self] req async throws -> Response in
                try await Self.dispatch(req, to: self)
            }
            app.on(method, "**") { [weak self] req async throws -> Response in
                try await Self.dispatch(req, to: self)
            }
        }
    }

    private static func dispatch(_ req: Request, to transport: VaporMCPTransport?) async throws -> Response {
        guard let transport else { throw Abort(.serviceUnavailable) }
        return await transport.answer(req)
    }

    // MARK: - Requests

    private func answer(_ req: Request) async -> Response {
        let request = Self.mcpRequest(from: req)
        if request.method == "GET", (request.header("accept") ?? "").contains("text/event-stream") {
            return openStream(for: request)
        }
        guard let handler else {
            return Self.response(MCPHTTPResponse(status: 503,
                                                 headers: ["Content-Type": "text/plain; charset=utf-8"],
                                                 body: Data("no handler".utf8)))
        }
        let reply = await withCheckedContinuation { (continuation: CheckedContinuation<MCPHTTPResponse, Never>) in
            handler(request) { continuation.resume(returning: $0) }
        }
        return Self.response(reply)
    }

    private func openStream(for request: MCPHTTPRequest) -> Response {
        let stream = VaporMCPEventStream()
        guard onStream?(request, stream) == true else {
            return Self.response(MCPHTTPResponse(status: 401,
                                                 headers: ["Content-Type": "text/plain; charset=utf-8"],
                                                 body: Data("Unauthorized".utf8)))
        }
        let previousOnClose = stream.onClose
        stream.onClose = { [weak self, weak stream] in
            previousOnClose?()
            guard let self, let stream else { return }
            self.lock.lock()
            self.streams.removeAll { $0 === stream }
            self.lock.unlock()
        }
        lock.lock()
        if !stream.isClosed {
            streams.append(stream)
        }
        lock.unlock()

        let interval = max(heartbeatInterval, 0.05)
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: "Content-Type", value: "text/event-stream")
        headers.replaceOrAdd(name: "Cache-Control", value: "no-cache")
        return Response(status: .ok, headers: headers, body: .init(managedAsyncStream: { writer in
            // A comment frame first, so the peer receives the response head at once.
            stream.ping()
            let heartbeat = Task {
                while true {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    stream.ping()
                }
            }
            defer {
                heartbeat.cancel()
                stream.close()
            }
            // Vapor ends the response when this returns, and fails it when this throws.
            for await frame in stream.frames {
                try await writer.write(.buffer(ByteBuffer(string: frame)))
            }
        }))
    }

    private static func mcpRequest(from req: Request) -> MCPHTTPRequest {
        var headers: [String: String] = [:]
        for (name, value) in req.headers {
            headers[name.lowercased()] = value
        }
        var path = req.url.path
        if let query = req.url.query, !query.isEmpty {
            path += "?" + query
        }
        var body = Data()
        if let buffer = req.body.data {
            body = Data(buffer.readableBytesView)
        }
        return MCPHTTPRequest(method: req.method.rawValue, path: path, headers: headers, body: body)
    }

    private static func response(_ reply: MCPHTTPResponse) -> Response {
        var headers = HTTPHeaders()
        for (name, value) in reply.headers {
            headers.replaceOrAdd(name: name, value: value)
        }
        return Response(status: HTTPStatus(statusCode: reply.status),
                        headers: headers,
                        body: .init(data: reply.body))
    }
}

/// Carries the result of the async start-up back to the thread waiting for it.
private final class StartOutcome {
    var result: Result<(Application, UInt16), Error>?
}

/// One server-sent-events channel. `MCPService` writes frames into it, the
/// response body drains `frames`, and closing it ends the response.
final class VaporMCPEventStream: MCPEventStream {
    /// Frames waiting for the response body to write them.
    let frames: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var closed = false
    var onClose: (() -> Void)?

    init() {
        var capturedContinuation: AsyncStream<String>.Continuation?
        frames = AsyncStream<String>(bufferingPolicy: .unbounded) { capturedContinuation = $0 }
        continuation = capturedContinuation!
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    /// Sends `object` as one `event: message` frame of JSON.
    func send(_ object: [String: Any]) {
        guard !isClosed else { return }
        let json = String(decoding: MCPWire.json(object), as: UTF8.self)
        continuation.yield("event: message\ndata: \(json)\n\n")
    }

    /// Writes an SSE comment frame, which clients ignore.
    func ping() {
        guard !isClosed else { return }
        continuation.yield(": ping\n\n")
    }

    func close() {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        let callback = onClose
        lock.unlock()
        continuation.finish()
        callback?()
    }
}
