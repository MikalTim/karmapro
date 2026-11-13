// by cipher.org.uk
import Foundation

/// The state of one background job, as the front end sees it.
public struct JobDTO: Codable, Sendable {
    public var id: String
    /// What the job does ("index", "scan", "search", ...).
    public var kind: String
    /// "running", "completed", "failed" or "cancelled".
    public var status: String
    public var done: Int
    public var total: Int
    public var stage: String
    public var error: String?
    /// The result, already encoded as JSON. It is spliced into `encoded()` as is
    /// and is not part of the Codable form.
    public var resultJSON: Data?

    private enum CodingKeys: String, CodingKey {
        case id, kind, status, done, total, stage, error
    }

    /// The JSON for this job: the fields above plus `"result": <resultJSON>` when there is a result.
    public func encoded() -> Data {
        var data = KarmaJSON.data(self)
        guard let result = resultJSON, data.last == UInt8(ascii: "}") else { return data }
        data.removeLast()
        data.append(Data(",\"result\":".utf8))
        data.append(result)
        data.append(UInt8(ascii: "}"))
        return data
    }
}

/// What a job's work closure uses to report progress and to see a cancel request.
public final class JobContext: @unchecked Sendable {
    let id: String
    private let center: KarmaJobCenter

    init(id: String, center: KarmaJobCenter) {
        self.id = id
        self.center = center
    }

    public func progress(done: Int, total: Int, stage: String = "") {
        center.update(id: id, done: done, total: total, stage: stage)
    }

    public var isCancelled: Bool { center.isCancelled(id: id) }

    /// An engine cancellation token that is cancelled when the job is.
    func cancellationToken() -> VariableFlowCancellation {
        center.makeCancellation(id: id)
    }
}

/// Runs long operations (index builds, scans, searches, training) on background
/// threads and keeps their progress and results so a front end can poll or
/// listen for them. Progress and completion are also posted on `KarmaEventBus`.
public final class KarmaJobCenter: @unchecked Sendable {
    public static let shared = KarmaJobCenter()

    /// How long a finished job is kept, and how many (the same limits as `ScanJobRunner.prune`).
    static let retention: TimeInterval = 2 * 60 * 60
    static let retainedCount = 100
    static let progressInterval: TimeInterval = 0.25

    private final class Job {
        var dto: JobDTO
        var cancelRequested = false
        var lastProgressEvent = Date.distantPast
        var finishedAt: Date?
        var tokens: [VariableFlowCancellation] = []
        init(dto: JobDTO) { self.dto = dto }
    }

    private let lock = NSLock()
    private var jobs: [String: Job] = [:]
    private let bus: KarmaEventBus

    public init(bus: KarmaEventBus = .shared) {
        self.bus = bus
    }

    /// Starts `work` on a background queue and returns the job's id at once.
    /// The returned data is the job's result (JSON), or nil. An error thrown by
    /// `work` fails the job with its description; a cancel request that is still
    /// set when `work` returns marks it cancelled and keeps the partial result.
    func start(kind: String, _ work: @escaping (JobContext) throws -> Data?) -> String {
        let id = UUID().uuidString.lowercased()
        let job = Job(dto: JobDTO(id: id, kind: kind, status: "running", done: 0, total: 0, stage: ""))
        lock.lock()
        prune()
        jobs[id] = job
        lock.unlock()
        post(progress: job.dto)
        job.lastProgressEvent = Date()

        let context = JobContext(id: id, center: self)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var result: Data?
            var failure: Error?
            do {
                result = try work(context)
            } catch {
                failure = error
            }
            finish(id: id, result: result, failure: failure)
        }
        return id
    }

    public func job(_ id: String) -> JobDTO? {
        lock.lock()
        defer { lock.unlock() }
        return jobs[id]?.dto
    }

    /// Asks a running job to stop. Returns the job's current state, or nil for an unknown id.
    @discardableResult
    public func cancel(_ id: String) -> JobDTO? {
        lock.lock()
        defer { lock.unlock() }
        guard let job = jobs[id] else { return nil }
        if job.dto.status == "running" {
            job.cancelRequested = true
            job.dto.stage = "cancelling"
            for token in job.tokens { token.cancel() }
        }
        return job.dto
    }

    fileprivate func isCancelled(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return jobs[id]?.cancelRequested ?? true
    }

    /// A token the engine can poll that this job's `cancel` flips (and that starts out flipped if the job was already cancelled).
    fileprivate func makeCancellation(id: String) -> VariableFlowCancellation {
        let token = VariableFlowCancellation()
        lock.lock()
        defer { lock.unlock() }
        guard let job = jobs[id] else {
            token.cancel()
            return token
        }
        if job.cancelRequested { token.cancel() }
        job.tokens.append(token)
        return token
    }

    fileprivate func update(id: String, done: Int, total: Int, stage: String) {
        lock.lock()
        guard let job = jobs[id], job.dto.status == "running" else {
            lock.unlock()
            return
        }
        job.dto.done = done
        job.dto.total = total
        if !stage.isEmpty && !job.cancelRequested { job.dto.stage = stage }
        let now = Date()
        let due = now.timeIntervalSince(job.lastProgressEvent) >= Self.progressInterval
        if due { job.lastProgressEvent = now }
        let snapshot = job.dto
        lock.unlock()
        if due { post(progress: snapshot) }
    }

    private func finish(id: String, result: Data?, failure: Error?) {
        lock.lock()
        guard let job = jobs[id] else {
            lock.unlock()
            return
        }
        if let failure {
            job.dto.status = "failed"
            job.dto.error = failure.localizedDescription
        } else if job.cancelRequested {
            job.dto.status = "cancelled"
            job.dto.resultJSON = result
        } else {
            job.dto.status = "completed"
            job.dto.resultJSON = result
            if job.dto.total > 0 { job.dto.done = job.dto.total }
        }
        job.finishedAt = Date()
        let snapshot = job.dto
        lock.unlock()
        post(progress: snapshot)
        bus.post("job.finished", JobFinishedEvent(id: snapshot.id, kind: snapshot.kind, status: snapshot.status))
    }

    private func post(progress dto: JobDTO) {
        bus.post("job.progress", JobProgressEvent(id: dto.id, kind: dto.kind, done: dto.done, total: dto.total, stage: dto.stage))
    }

    /// Drops finished jobs older than the retention time, then the oldest beyond the count. Call with the lock held.
    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        for (id, job) in jobs where (job.finishedAt ?? .distantFuture) < cutoff {
            jobs[id] = nil
        }
        let finished = jobs.filter { $0.value.finishedAt != nil }
            .sorted { ($0.value.finishedAt ?? .distantPast) < ($1.value.finishedAt ?? .distantPast) }
        if finished.count > Self.retainedCount {
            for (id, _) in finished.prefix(finished.count - Self.retainedCount) { jobs[id] = nil }
        }
    }
}
