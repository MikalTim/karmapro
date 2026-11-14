// by cipher.org.uk
import Foundation

/// The state of the MCP service, as shown in Settings.
public struct MCPStateDTO: Codable, Sendable {
    public var running: Bool
    /// The endpoint to give a client, token included.
    public var url: String
    public var clientConfig: String
    public var port: Int
    public var allowAI: Bool
    public var autoStart: Bool
    public var scanCount: Int
    public var lastError: String

    public init(running: Bool, url: String, clientConfig: String, port: Int, allowAI: Bool,
                autoStart: Bool, scanCount: Int, lastError: String) {
        self.running = running
        self.url = url
        self.clientConfig = clientConfig
        self.port = port
        self.allowAI = allowAI
        self.autoStart = autoStart
        self.scanCount = scanCount
        self.lastError = lastError
    }
}

/// The MCP service (Karma Pro as a tool server for AI clients).
public enum KarmaMCP {
    /// Supplies the HTTP listener the service runs on. Front ends call this
    /// once at startup.
    public static func installTransport(_ make: @escaping () -> MCPTransport) {
        MCPService.makeTransport = make
        // The web server has no main run loop to deliver change callbacks on.
        MCPService.changeQueue = DispatchQueue(label: "app.karmapro.mcp.changes")
        // The web server reports every MCP state change to the browser tabs through the event bus.
        MCPService.shared.onChange = { KarmaEventBus.shared.post("mcp.changed", KarmaMCP.state()) }
    }

    public static func state() -> MCPStateDTO {
        let service = MCPService.shared
        return MCPStateDTO(running: service.isRunning,
                           url: service.url,
                           clientConfig: service.clientConfig,
                           port: Int(service.port),
                           allowAI: service.allowAI,
                           autoStart: service.autoStart,
                           scanCount: service.scanCount,
                           lastError: service.lastError ?? "")
    }

    /// Reports every state change (start, stop, new scan, token change).
    public static func onChange(_ handler: @escaping () -> Void) {
        MCPService.shared.onChange = handler
    }

    public static func toggle() throws {
        let service = MCPService.shared
        if service.isRunning {
            service.stop()
        } else {
            try service.start()
        }
    }

    public static func stop() {
        MCPService.shared.stop()
    }

    public static func setAllowAI(_ value: Bool) {
        MCPService.shared.allowAI = value
    }

    public static func setAutoStart(_ value: Bool) {
        MCPService.shared.autoStart = value
    }

    public static func rotateToken() {
        MCPService.shared.rotateToken()
    }

    /// Starts the service when the user turned "start automatically" on, as
    /// the app does at launch. A failure is recorded in `state().lastError`.
    public static func startIfAutoStart() {
        guard MCPService.shared.autoStart else { return }
        try? MCPService.shared.start()
    }
}
