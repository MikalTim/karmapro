// by cipher.org.uk
import Foundation

/// Carries live updates from the services to whoever is listening: for the web
/// front end, the server-sent-events stream at `GET /api/events`.
///
/// Event types and their payloads (JSON):
///  - `job.progress`      `{id, kind, done, total, stage}` (at most one per job per 250 ms, plus the first and last)
///  - `job.finished`      `{id, kind, status}`
///  - `workspace.changed` `{root, name}`
///  - `bugs.changed`      `{openCount}`
///  - `notes.changed`, `wiki.changed`, `ml.changed`   `{}`
///  - `ai.stream`         `{seq, kind, text, level?}`
///  - `pr.changed`        the full pull-request state
///  - `pr.notify`         `{items: [{repoID, prID, title, body}], allowSound}`
///  - `pr.review`         `{state: "opened" | "closed"}`
///  - `update.changed`    the update state
///  - `mcp.changed`       the MCP service state
public final class KarmaEventBus: @unchecked Sendable {
    public static let shared = KarmaEventBus()

    private let lock = NSLock()
    private var handlers: [UUID: (String, Data) -> Void] = [:]

    public init() {}

    /// Registers a handler called with each event's type and its JSON payload.
    /// Handlers run synchronously on the thread that posts, so they must be quick.
    public func subscribe(_ handler: @escaping (String, Data) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        handlers[id] = handler
        lock.unlock()
        return id
    }

    public func unsubscribe(_ id: UUID) {
        lock.lock()
        handlers[id] = nil
        lock.unlock()
    }

    /// Encodes `payload` once and passes it to every handler.
    func post<T: Encodable>(_ type: String, _ payload: T) {
        let data = KarmaJSON.data(payload)
        lock.lock()
        let current = Array(handlers.values)
        lock.unlock()
        for handler in current { handler(type, data) }
    }

    /// Posts an event whose payload is `{}`.
    func post(_ type: String) {
        post(type, EmptyPayload())
    }
}

/// The `{}` payload of events that only say "something changed, fetch again".
struct EmptyPayload: Codable {}

public struct JobProgressEvent: Codable, Sendable {
    public var id: String
    public var kind: String
    public var done: Int
    public var total: Int
    public var stage: String
}

public struct JobFinishedEvent: Codable, Sendable {
    public var id: String
    public var kind: String
    public var status: String
}

public struct WorkspaceChangedEvent: Codable, Sendable {
    public var root: String?
    public var name: String?
}

public struct BugsChangedEvent: Codable, Sendable {
    public var openCount: Int
}
