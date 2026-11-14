// by cipher.org.uk
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Bayesian classifier models: training from a folder of patches, import and
/// export, project scans, and the heatmap of their results. Ports
/// `MLTrainingWindowController`, `MLScanWindowController` and
/// `HeatmapWindowController`.
public enum MLService {

    // MARK: - DTOs

    /// A trained model in the library.
    public struct MLModelDTO: Codable, Sendable {
        public var name: String

        public init(name: String) {
            self.name = name
        }
    }

    /// A language choice with the file extensions it covers.
    public struct MLLanguageDTO: Codable, Sendable {
        public var name: String
        public var extensions: [String]

        public init(name: String, extensions: [String]) {
            self.name = name
            self.extensions = extensions
        }
    }

    /// What the training and scan forms offer.
    public struct MLOptionsDTO: Codable, Sendable {
        /// Languages a model can be trained on (every language except "All Languages").
        public var trainingLanguages: [MLLanguageDTO]
        /// Languages a scan can cover; "All Languages" has no extensions and means every file.
        public var scanLanguages: [MLLanguageDTO]
        /// The model list line of the training window ("Saved models: …" or "No trained models yet.").
        public var modelsSummary: String
        /// Why a scan cannot start, or nil when it can.
        public var unavailableText: String?
        public var canScan: Bool
        /// Flag threshold slider bounds and default, in percent.
        public var thresholdMin: Double
        public var thresholdMax: Double
        public var thresholdDefault: Double

        public init(trainingLanguages: [MLLanguageDTO], scanLanguages: [MLLanguageDTO], modelsSummary: String,
                    unavailableText: String?, canScan: Bool, thresholdMin: Double, thresholdMax: Double,
                    thresholdDefault: Double) {
            self.trainingLanguages = trainingLanguages
            self.scanLanguages = scanLanguages
            self.modelsSummary = modelsSummary
            self.unavailableText = unavailableText
            self.canScan = canScan
            self.thresholdMin = thresholdMin
            self.thresholdMax = thresholdMax
            self.thresholdDefault = thresholdDefault
        }
    }

    /// Result of a training job.
    public struct MLTrainResultDTO: Codable, Sendable {
        public var saved: Bool
        public var patches: Int
        public var lines: Int
        /// The status line the training window shows.
        public var statusText: String
        public var model: MLModelDTO?

        public init(saved: Bool, patches: Int, lines: Int, statusText: String, model: MLModelDTO?) {
            self.saved = saved
            self.patches = patches
            self.lines = lines
            self.statusText = statusText
            self.model = model
        }
    }

    /// One heatmap cell: a scanned file and how many of its lines reach the threshold.
    public struct HeatmapCellDTO: Codable, Sendable {
        public var path: String
        /// The path relative to the project root (the last path component outside it).
        public var name: String
        public var flagged: Int
        /// flagged ÷ the hottest file's count, 0...1. The colour ramp runs cold (blue) to hot (red) on this value.
        public var intensity: Double

        public init(path: String, name: String, flagged: Int, intensity: Double) {
            self.path = path
            self.name = name
            self.flagged = flagged
            self.intensity = intensity
        }
    }

    /// The heatmap of the most recent scan, hottest file first.
    public struct HeatmapDTO: Codable, Sendable {
        public var modelName: String
        /// The threshold of the scan, in percent.
        public var thresholdPercent: Int
        public var totalFiles: Int
        public var totalFlagged: Int
        public var maxFlagged: Int
        /// The heatmap's summary line.
        public var summary: String
        public var cells: [HeatmapCellDTO]

        public init(modelName: String, thresholdPercent: Int, totalFiles: Int, totalFlagged: Int, maxFlagged: Int,
                    summary: String, cells: [HeatmapCellDTO]) {
            self.modelName = modelName
            self.thresholdPercent = thresholdPercent
            self.totalFiles = totalFiles
            self.totalFlagged = totalFlagged
            self.maxFlagged = maxFlagged
            self.summary = summary
            self.cells = cells
        }
    }

    /// Result of a scan job.
    public struct MLScanResultDTO: Codable, Sendable {
        public var modelName: String
        public var thresholdPercent: Int
        public var totalFiles: Int
        public var totalLines: Int
        public var flaggedLines: Int
        /// The status line the scan window shows.
        public var statusText: String
        public var heatmap: HeatmapDTO

        public init(modelName: String, thresholdPercent: Int, totalFiles: Int, totalLines: Int, flaggedLines: Int,
                    statusText: String, heatmap: HeatmapDTO) {
            self.modelName = modelName
            self.thresholdPercent = thresholdPercent
            self.totalFiles = totalFiles
            self.totalLines = totalLines
            self.flaggedLines = flaggedLines
            self.statusText = statusText
            self.heatmap = heatmap
        }
    }

    // MARK: - Shared state

    /// Guards `MLScanResultStore`, which is not thread-safe, and the in-flight job ids.
    private static let lock = NSLock()
    private static var trainingJobID: String?
    private static var scanJobID: String?

    /// The ML training and scan windows use these tiers and this default.
    private static let thresholdMin = 1.0
    private static let thresholdMax = 100.0
    private static let thresholdDefault = 70.0

    private static let allLanguagesName = "All Languages"
    private static let modelFileExtensions: Set<String> = ["karmamodel", "json"]

    // MARK: - Queries

    /// Every model in the library, sorted by name (the list the training window shows).
    public static func models() -> [MLModelDTO] {
        ModelStore.shared.listModels().map { MLModelDTO(name: $0) }
    }

    /// The choices and availability the training and scan forms show.
    public static func options() -> MLOptionsDTO {
        let names = ModelStore.shared.listModels()
        let root = KarmaWorkspace.shared.read { $0.root }
        let unavailable: String?
        if root == nil {
            unavailable = "Open a source folder before scanning."
        } else if names.isEmpty {
            unavailable = "Train a model first (Train Bayesian Classifier)."
        } else {
            unavailable = nil
        }
        let languages = Language.supported.map {
            MLLanguageDTO(name: $0.name, extensions: $0.extensions.sorted())
        }
        return MLOptionsDTO(
            trainingLanguages: languages.filter { $0.name != allLanguagesName },
            scanLanguages: languages,
            modelsSummary: names.isEmpty ? "No trained models yet." : "Saved models: " + names.joined(separator: ", "),
            unavailableText: unavailable,
            canScan: unavailable == nil,
            thresholdMin: thresholdMin,
            thresholdMax: thresholdMax,
            thresholdDefault: thresholdDefault)
    }

    /// The heatmap of the most recent scan. Empty when no scan has run.
    public static func heatmap() -> HeatmapDTO {
        let root = KarmaWorkspace.shared.read { $0.root }
        lock.lock()
        defer { lock.unlock() }
        return heatmapSnapshot(root: root)
    }

    // MARK: - Training

    /// Trains a model named `name` on the +/- lines of the patches under `folder`, restricted to
    /// `language`. Returns the id of the `ml-train` job; its result is an `MLTrainResultDTO`.
    public static func train(folder: String, language: String, name: String) throws -> String {
        let folder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.isEmpty else {
            throw KarmaServiceError.invalid("Use “Choose Patch Folder…” to select a directory of patches first.")
        }
        let modelName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            throw KarmaServiceError.invalid("Enter a name for the training model.")
        }
        guard let selected = Language.supported.first(where: { $0.name == language && $0.name != allLanguagesName }) else {
            throw KarmaServiceError.invalid("Choose a language to train on.")
        }
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        guard isDirectory(root) else { throw KarmaServiceError.notADirectory(folder) }

        lock.lock()
        defer { lock.unlock() }
        if let running = trainingJobID, KarmaJobCenter.shared.job(running)?.status == "running" {
            throw KarmaServiceError.busy("Training is already running.")
        }

        let model = BayesianClassifier(name: modelName)
        let jobID = KarmaJobCenter.shared.start(kind: "ml-train") { context in
            context.progress(done: 0, total: 1, stage: "Reading patches…")
            let (patches, lines) = PatchTrainer.train(model: model, in: root, language: selected) { done, total in
                context.progress(done: done, total: total, stage: "Reading patches…")
            }
            let saved = ModelStore.shared.save(model)
            if saved {
                KarmaEventBus.shared.post("ml.changed")
            }
            let status = saved
                ? "Trained on \(patches) patch(es), \(lines) lines. Model “\(modelName)” saved."
                : "Training finished but failed to save the model."
            let result = MLTrainResultDTO(saved: saved, patches: patches, lines: lines, statusText: status,
                                          model: saved ? MLModelDTO(name: modelName) : nil)
            return KarmaJSON.data(result)
        }
        trainingJobID = jobID
        return jobID
    }

    // MARK: - Import and export

    /// The library file of a model, as a `.karmamodel` download.
    public static func exportModel(name: String) throws -> (fileName: String, data: Data) {
        let names = ModelStore.shared.listModels()
        guard !names.isEmpty else {
            throw KarmaServiceError.invalid("There are no trained models to export yet.")
        }
        guard names.contains(name) else {
            throw KarmaServiceError.notFound("Model “\(name)” does not exist.")
        }
        guard let model = ModelStore.shared.load(named: name) else {
            throw KarmaServiceError.notFound("Model “\(name)” could not be loaded.")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-model-\(UUID().uuidString).karmamodel")
        defer { try? FileManager.default.removeItem(at: url) }
        guard ModelStore.shared.export(model, to: url), let data = try? Data(contentsOf: url) else {
            throw KarmaServiceError.invalid("Could not write the model file.")
        }
        return ("\(name).karmamodel", data)
    }

    /// Adds a model file uploaded by the browser to the library. `fileName` must end in `.karmamodel` or `.json`.
    public static func importModel(data: Data, fileName: String) throws -> MLModelDTO {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard modelFileExtensions.contains(ext) else {
            throw KarmaServiceError.invalid("Choose a Karma Pro model file (.karmamodel or .json).")
        }
        let result = ModelStore.shared.importModel(fromData: data)
        guard let model = result.model else {
            throw KarmaServiceError.invalid(result.error)
        }
        KarmaEventBus.shared.post("ml.changed")
        return MLModelDTO(name: model.name)
    }

    /// Downloads a raw model file from `urlString` and adds it to the library. Blocks the calling
    /// thread until the download finishes (at most 60 seconds).
    public static func importModel(urlString: String) throws -> MLModelDTO {
        let raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else {
            throw KarmaServiceError.invalid("Enter a valid web address.")
        }
        let data = try download(url)
        let result = ModelStore.shared.importModel(fromData: data)
        guard let model = result.model else {
            throw KarmaServiceError.invalid("Import failed: \(result.error)")
        }
        KarmaEventBus.shared.post("ml.changed")
        return MLModelDTO(name: model.name)
    }

    // MARK: - Scanning

    /// Scans every source file under the open project with the model `name`, flagging lines whose
    /// bad probability reaches `threshold` percent. `extensions` empty means every file. Returns the id
    /// of the `ml-scan` job; its result is an `MLScanResultDTO`, and the results feed the source viewer.
    public static func scan(model name: String, extensions: [String], threshold: Double) throws -> String {
        let root = try KarmaWorkspace.shared.requireRoot()
        let modelName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty, modelName != "-- no models --",
              let model = ModelStore.shared.load(named: modelName) else {
            throw KarmaServiceError.invalid("Choose a trained model.")
        }
        guard threshold >= thresholdMin, threshold <= thresholdMax else {
            throw KarmaServiceError.invalid("The flag threshold must be between \(Int(thresholdMin))% and \(Int(thresholdMax))%.")
        }
        let exts = Set(extensions.map { $0.lowercased() })
        let effective = max(0.01, threshold / 100.0)

        lock.lock()
        defer { lock.unlock() }
        if let running = scanJobID, KarmaJobCenter.shared.job(running)?.status == "running" {
            throw KarmaServiceError.busy("A scan is already running.")
        }

        let jobID = KarmaJobCenter.shared.start(kind: "ml-scan") { context in
            context.progress(done: 0, total: 1, stage: "Scanning…")
            let outcome = BayesianProjectScanner.scanProject(root: root, model: model, extensions: exts,
                                                             threshold: effective) { done, total in
                context.progress(done: done, total: total, stage: "Scanning…")
            }
            let flagged = outcome.results.values.reduce(0) { $0 + $1.count }
            let pct = Int(effective * 100)
            lock.lock()
            MLScanResultStore.shared.setResults(outcome.results, modelName: modelName, threshold: effective)
            let heatmap = heatmapSnapshot(root: root)
            lock.unlock()
            KarmaEventBus.shared.post("ml.changed")

            let status = "Scanned \(outcome.totalFiles) file(s), \(outcome.totalLines) line(s) with model “\(modelName)”. \(flagged) line(s) >=\(pct)% flagged."
            let result = MLScanResultDTO(modelName: modelName, thresholdPercent: pct, totalFiles: outcome.totalFiles,
                                         totalLines: outcome.totalLines, flaggedLines: flagged,
                                         statusText: status, heatmap: heatmap)
            return KarmaJSON.data(result)
        }
        scanJobID = jobID
        return jobID
    }

    // MARK: - Helpers

    /// Builds the heatmap from `MLScanResultStore`. The caller must hold `lock`.
    private static func heatmapSnapshot(root: URL?) -> HeatmapDTO {
        let store = MLScanResultStore.shared
        let entries = store.flaggedCounts()
        let maxFlags = entries.first?.flagged ?? 0
        let cells = entries.map { entry in
            HeatmapCellDTO(path: entry.path,
                           name: store.displayPath(entry.path, under: root),
                           flagged: entry.flagged,
                           intensity: maxFlags == 0 ? 0 : Double(entry.flagged) / Double(maxFlags))
        }
        let totalFlagged = entries.reduce(0) { $0 + $1.flagged }
        let summary: String
        if let hottest = entries.first {
            let name = store.displayPath(hottest.path, under: root)
            summary = "\(entries.count) file(s) flagged, \(totalFlagged) line(s) total. Hottest: \(name) (\(hottest.flagged))."
        } else {
            summary = "No scan results yet — run an ML Project Scan."
        }
        return HeatmapDTO(modelName: store.currentModelName(),
                          thresholdPercent: Int(store.activeThreshold * 100),
                          totalFiles: entries.count,
                          totalFlagged: totalFlagged,
                          maxFlagged: maxFlags,
                          summary: summary,
                          cells: cells)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Synchronous GET for `importModel(urlString:)`, with the window's status texts as error messages.
    private static func download(_ url: URL) throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let semaphore = DispatchSemaphore(value: 0)
        var received: (data: Data?, response: URLResponse?, error: Error?) = (nil, nil, nil)
        URLSession.shared.dataTask(with: request) { data, response, error in
            received = (data, response, error)
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 70) == .success else {
            throw KarmaServiceError.invalid("Import failed: the download timed out.")
        }
        if let error = received.error {
            throw KarmaServiceError.invalid("Import failed: \(error.localizedDescription)")
        }
        if let http = received.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw KarmaServiceError.invalid("Import failed: server returned HTTP \(http.statusCode).")
        }
        guard let data = received.data, !data.isEmpty else {
            throw KarmaServiceError.invalid("Import failed: no data received.")
        }
        return data
    }
}
