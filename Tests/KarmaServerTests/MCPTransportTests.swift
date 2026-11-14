// by cipher.org.uk
#if WebServer
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import KarmaCore
import XCTest
@testable import KarmaServer

/// A value written on one thread and read on another.
private final class Box<Value> {
    private let lock = NSLock()
    private var stored: Value?

    func set(_ value: Value) {
        lock.lock()
        stored = value
        lock.unlock()
    }

    var value: Value? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

/// Receives a streamed response chunk by chunk, as the bytes arrive.
private final class StreamProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let chunks: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var head: HTTPURLResponse?

    override init() {
        var captured: AsyncStream<Data>.Continuation?
        chunks = AsyncStream<Data>(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured!
        super.init()
    }

    /// The response head; it is set before the first chunk is delivered.
    var response: HTTPURLResponse? {
        lock.lock()
        defer { lock.unlock() }
        return head
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        head = response as? HTTPURLResponse
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation.finish()
    }
}

/// Exercises the Vapor MCP listener over real loopback sockets, on port 0 so
/// no fixed port is taken. The MCPService endpoint is not covered here: that
/// service persists its token and last port in UserDefaults.standard, so the
/// test would write to the real defaults.
final class MCPTransportTests: XCTestCase {
    private var transports: [VaporMCPTransport] = []

    override func tearDown() {
        transports.forEach { $0.stop() }
        transports = []
        super.tearDown()
    }

    private func makeTransport() -> VaporMCPTransport {
        let transport = VaporMCPTransport()
        transports.append(transport)
        return transport
    }

    private func url(_ port: UInt16, _ path: String) throws -> URL {
        try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(path)"))
    }

    private func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = 10
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    func testHandlerAnswersPostWithItsStatusHeadersAndBody() async throws {
        let transport = makeTransport()
        let port = try transport.start(port: 0)
        let seen = Box<MCPHTTPRequest>()
        transport.handler = { request, reply in
            seen.set(request)
            reply(MCPHTTPResponse(status: 202,
                                  headers: ["Content-Type": "application/json", "Mcp-Session-Id": "abc"],
                                  body: Data("{\"ok\":true}".utf8)))
        }
        var request = URLRequest(url: try url(port, "/mcp/secret?x=1"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let sentBody = Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}".utf8)
        request.httpBody = sentBody

        let (data, response) = try await fetch(request)

        XCTAssertEqual(response.statusCode, 202)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Mcp-Session-Id"), "abc")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"ok\":true}")
        let received = try XCTUnwrap(seen.value)
        XCTAssertEqual(received.method, "POST")
        XCTAssertEqual(received.path, "/mcp/secret?x=1")
        XCTAssertEqual(received.header("Content-Type"), "application/json")
        XCTAssertEqual(received.body, sentBody)
    }

    func testRootPathReachesTheHandler() async throws {
        let transport = makeTransport()
        let port = try transport.start(port: 0)
        transport.handler = { _, reply in
            reply(MCPHTTPResponse(status: 200, body: Data("root".utf8)))
        }
        var request = URLRequest(url: try url(port, "/"))
        request.httpMethod = "POST"

        let (data, response) = try await fetch(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "root")
    }

    func testEventStreamIsRefusedWithPlain401WhenOnStreamDeclines() async throws {
        let transport = makeTransport()
        let port = try transport.start(port: 0)
        transport.onStream = { _, _ in false }
        var request = URLRequest(url: try url(port, "/mcp/secret"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (data, response) = try await fetch(request)

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "text/plain; charset=utf-8")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "Unauthorized")
    }

    func testEventStreamForwardsSentObjectAsMessageEvent() async throws {
        let transport = makeTransport()
        let port = try transport.start(port: 0)
        let opened = Box<MCPEventStream>()
        transport.onStream = { _, stream in
            opened.set(stream)
            return true
        }
        var request = URLRequest(url: try url(port, "/mcp/secret"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let probe = StreamProbe()
        let session = URLSession(configuration: .ephemeral, delegate: probe, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: request).resume()

        // The first chunk is the transport's opening comment frame, so the stream is registered by now.
        var collected = Data()
        var sent = false
        for await chunk in probe.chunks {
            collected.append(chunk)
            if !sent {
                sent = true
                let stream = try XCTUnwrap(opened.value)
                stream.send(["jsonrpc": "2.0", "method": "notifications/tools/list_changed", "params": ["count": 2]])
            }
            let text = String(decoding: collected, as: UTF8.self)
            if text.contains("event: message\n"), text.hasSuffix("\n\n") {
                break
            }
        }
        opened.value?.close()

        let http = try XCTUnwrap(probe.response)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Type"), "text/event-stream")
        let text = String(decoding: collected, as: UTF8.self)
        XCTAssertTrue(text.contains("event: message\ndata: "), text)
        let dataLine = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("data: ") })
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(dataLine.dropFirst("data: ".count).utf8)) as? [String: Any]
        )
        XCTAssertEqual(json["method"] as? String, "notifications/tools/list_changed")
        XCTAssertEqual((json["params"] as? [String: Any])?["count"] as? Int, 2)
    }

    func testClientDisconnectClosesTheEventStream() async throws {
        let transport = makeTransport()
        transport.heartbeatInterval = 0.1
        let port = try transport.start(port: 0)
        let opened = Box<MCPEventStream>()
        let openedExpectation = expectation(description: "stream opened")
        let closedExpectation = expectation(description: "stream closed")
        transport.onStream = { _, stream in
            stream.onClose = { closedExpectation.fulfill() }
            opened.set(stream)
            openedExpectation.fulfill()
            return true
        }
        var request = URLRequest(url: try url(port, "/mcp/secret"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request).resume()

        await fulfillment(of: [openedExpectation], timeout: 10)
        session.invalidateAndCancel()
        await fulfillment(of: [closedExpectation], timeout: 10)

        XCTAssertEqual(opened.value?.isClosed, true)
    }

    func testStopFreesThePortAndIsSafeTwice() throws {
        let first = VaporMCPTransport()
        let port = try first.start(port: 0)
        first.stop()
        first.stop()

        let second = VaporMCPTransport()
        defer { second.stop() }
        XCTAssertEqual(try second.start(port: port), port)
    }

    func testStartThrowsWhenThePortIsTaken() throws {
        let first = makeTransport()
        let port = try first.start(port: 0)
        let second = makeTransport()
        XCTAssertThrowsError(try second.start(port: port))
    }
}
#endif
