// by cipher.org.uk
import Foundation

/// One HTTP request received by an MCP transport.
public struct MCPHTTPRequest {
    public let method: String
    /// The request target, including any query string.
    public let path: String
    /// Header names in lower case.
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }
}

/// The reply to an `MCPHTTPRequest`.
public struct MCPHTTPResponse {
    public var status: Int = 200
    public var headers: [String: String] = [:]
    public var body: Data = Data()

    public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    static func json(_ object: Any) -> MCPHTTPResponse {
        MCPHTTPResponse(status: 200,
                        headers: ["Content-Type": "application/json"],
                        body: MCPCode.json(object))
    }

    static func text(_ status: Int, _ message: String) -> MCPHTTPResponse {
        MCPHTTPResponse(status: status,
                        headers: ["Content-Type": "text/plain; charset=utf-8"],
                        body: Data(message.utf8))
    }
}

/// A server-sent-events channel for one MCP client session.
public protocol MCPEventStream: AnyObject {
    var isClosed: Bool { get }
    /// Called once when the stream closes.
    var onClose: (() -> Void)? { get set }
    /// Sends `object` as one `event: message` frame of JSON.
    func send(_ object: [String: Any])
    func close()
}

/// The HTTP listener `MCPService` runs on. The AppKit app provides one built on
/// `Network.framework`; the web server provides one built on Vapor.
public protocol MCPTransport: AnyObject {
    /// Handlers may block (a scan_directory call waits briefly), so the
    /// transport must not call them on its listener's thread, and the handler
    /// answers through the callback.
    var handler: ((MCPHTTPRequest, @escaping (MCPHTTPResponse) -> Void) -> Void)? { get set }
    /// Called for a GET that asks for `text/event-stream`. Return false to
    /// refuse the stream; the peer then gets a plain 401.
    var onStream: ((MCPHTTPRequest, MCPEventStream) -> Bool)? { get set }
    var log: ((String) -> Void)? { get set }

    /// Binds `port` (0 = any free port) on the loopback address and returns the
    /// port that was bound. Throws when it cannot listen there.
    func start(port: UInt16) throws -> UInt16
    func stop()
}

/// Serialises a JSON-RPC value the way MCP replies are written.
public enum MCPWire {
    public static func json(_ object: Any) -> Data {
        MCPCode.json(object)
    }
}
