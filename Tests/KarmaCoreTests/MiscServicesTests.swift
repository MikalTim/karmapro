import Foundation
import XCTest
@testable import KarmaCore

/// The ML, AI settings, update, debugger and entry-point services, through their public API.
///
/// `ModelStore`, `ProviderStore` and `PromptStore` keep their files in the application support
/// folder, which Foundation derives from `HOME` and `XDG_DATA_HOME`. The class points both at a
/// temporary directory before any of those singletons is first used, so no test touches the real
/// library. `UserDefaults` keys the tests change are restored afterwards.
final class MiscServicesTests: XCTestCase {

    private static var isolatedHome: URL!
    private static var savedHome: String?
    private static var savedXDG: String?

    override class func setUp() {
        super.setUp()
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-misc-home-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        savedHome = ProcessInfo.processInfo.environment["HOME"]
        savedXDG = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        setenv("HOME", home.path, 1)
        setenv("XDG_DATA_HOME", home.path, 1)
        isolatedHome = home
    }

    override class func tearDown() {
        if let savedHome = savedHome { setenv("HOME", savedHome, 1) } else { unsetenv("HOME") }
        if let savedXDG = savedXDG { setenv("XDG_DATA_HOME", savedXDG, 1) } else { unsetenv("XDG_DATA_HOME") }
        try? FileManager.default.removeItem(at: isolatedHome)
        super.tearDown()
    }

    /// Fails loudly, before any test writes, if Foundation does not place the library under the temporary home.
    private func assertLibraryIsIsolated() throws {
        let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory,
                                                             in: .userDomainMask).first)
        guard support.path.hasPrefix(Self.isolatedHome.path) else {
            XCTFail("Application support is \(support.path), outside the isolated home; refusing to run.")
            throw XCTSkip("isolation not in effect")
        }
    }

    // MARK: - Helpers

    /// Polls until `condition` holds, so tests do not depend on how fast a background job runs.
    private func waitUntil(_ message: String, timeout: TimeInterval = 20, _ condition: () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for: \(message)", file: file, line: line)
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// Waits for a job to leave `running` and decodes its result.
    private func result<T: Decodable>(_ type: T.Type, job id: String,
                                      file: StaticString = #filePath, line: UInt = #line) throws -> T {
        waitUntil("job \(id)", { KarmaJobCenter.shared.job(id)?.status != "running" }, file: file, line: line)
        let job = try XCTUnwrap(KarmaJobCenter.shared.job(id), file: file, line: line)
        XCTAssertEqual(job.status, "completed", job.error ?? "", file: file, line: line)
        return try KarmaJSON.decoder.decode(type, from: try XCTUnwrap(job.resultJSON, file: file, line: line))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-misc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeFiles(_ files: [String: String], under root: URL) throws {
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Saves the given UserDefaults keys and restores them when the test ends.
    private func preserveDefaults(_ keys: [String]) {
        let defaults = UserDefaults.standard
        var saved: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) { saved[key] = value }
        }
        addTeardownBlock {
            for key in keys {
                if let value = saved[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }

    /// The error text a caller shows for a thrown service error.
    private func message(of error: Error) -> String {
        (error as NSError).localizedDescription
    }

    // MARK: - ML

    private static let patch = """
        --- a/src/vuln.c
        +++ b/src/vuln.c
        @@ -1,3 +1,3 @@
        -    strcpy(buf, argv[1]);
        +    strncpy(buf, argv[1], sizeof buf - 1);
        """

    private static let cSource = """
        #include <string.h>
        int main(int argc, char **argv) {
            char buf[16];
            strcpy(buf, argv[1]);
            return 0;
        }
        """

    func testTrainingListsTheModelAndExportImportRoundTrips() throws {
        try assertLibraryIsIsolated()
        let patches = try makeTemporaryDirectory()
        try writeFiles(["fixes/one.patch": Self.patch], under: patches)

        let jobID = try MLService.train(folder: patches.path, language: "C", name: "UnitTestModel")
        let trained = try result(MLService.MLTrainResultDTO.self, job: jobID)
        XCTAssertTrue(trained.saved)
        XCTAssertEqual(trained.patches, 1)
        XCTAssertEqual(trained.statusText, "Trained on 1 patch(es), \(trained.lines) lines. Model “UnitTestModel” saved.")
        XCTAssertTrue(MLService.models().map(\.name).contains("UnitTestModel"))
        XCTAssertTrue(MLService.options().modelsSummary.contains("UnitTestModel"))

        let exported = try MLService.exportModel(name: "UnitTestModel")
        XCTAssertEqual(exported.fileName, "UnitTestModel.karmamodel")
        XCTAssertFalse(exported.data.isEmpty)

        let imported = try MLService.importModel(data: exported.data, fileName: exported.fileName)
        XCTAssertEqual(imported.name, "UnitTestModel")

        XCTAssertThrowsError(try MLService.importModel(data: Data("not a model".utf8), fileName: "x.json")) {
            XCTAssertEqual(self.message(of: $0), "Not a valid Karma Pro model file.")
        }
        XCTAssertThrowsError(try MLService.importModel(data: exported.data, fileName: "x.txt")) {
            XCTAssertEqual(self.message(of: $0), "Choose a Karma Pro model file (.karmamodel or .json).")
        }
    }

    func testTrainingRejectsAMissingNameAndAnUnknownLanguage() throws {
        try assertLibraryIsIsolated()
        let patches = try makeTemporaryDirectory()
        XCTAssertThrowsError(try MLService.train(folder: patches.path, language: "C", name: "  ")) {
            XCTAssertEqual(self.message(of: $0), "Enter a name for the training model.")
        }
        XCTAssertThrowsError(try MLService.train(folder: patches.path, language: "All Languages", name: "X")) {
            XCTAssertEqual(self.message(of: $0), "Choose a language to train on.")
        }
    }

    func testScanRunsAsAJobAndFillsTheResultStore() throws {
        try assertLibraryIsIsolated()
        let patches = try makeTemporaryDirectory()
        try writeFiles(["fixes/one.patch": Self.patch], under: patches)
        _ = try result(MLService.MLTrainResultDTO.self,
                       job: try MLService.train(folder: patches.path, language: "C", name: "ScanModel"))

        let project = try makeTemporaryDirectory()
        try writeFiles(["src/vuln.c": Self.cSource], under: project)
        _ = try KarmaWorkspace.shared.open(root: project.path)

        let jobID = try MLService.scan(model: "ScanModel", extensions: ["c"], threshold: 50)
        let scanned = try result(MLService.MLScanResultDTO.self, job: jobID)
        XCTAssertEqual(scanned.modelName, "ScanModel")
        XCTAssertEqual(scanned.thresholdPercent, 50)
        XCTAssertEqual(scanned.totalFiles, 1)
        XCTAssertTrue(scanned.statusText.hasPrefix("Scanned 1 file(s)"))

        XCTAssertEqual(MLScanResultStore.shared.activeModelName, "ScanModel")
        XCTAssertTrue(MLScanResultStore.shared.anyResults())
        XCTAssertEqual(MLService.heatmap().modelName, "ScanModel")
    }

    // MARK: - AI settings

    func testProviderRulesAddUpdateAndDelete() throws {
        try assertLibraryIsIsolated()
        preserveDefaults(["AI.providerID"])

        XCTAssertThrowsError(try AISettingsService.addProvider(name: " ", baseURL: "https://a.example.com/v1",
                                                               requiresAPIKey: false, apiKey: "")) {
            XCTAssertEqual(self.message(of: $0), "Enter a name for this provider.")
        }
        XCTAssertThrowsError(try AISettingsService.addProvider(name: "Bad URL", baseURL: "not a url",
                                                               requiresAPIKey: false, apiKey: "")) {
            XCTAssertEqual(self.message(of: $0), "Enter a valid base URL, e.g. https://api.example.com/v1")
        }
        XCTAssertThrowsError(try AISettingsService.addProvider(name: "Keyed", baseURL: "https://a.example.com/v1",
                                                               requiresAPIKey: true, apiKey: "  ")) {
            XCTAssertEqual(self.message(of: $0), "This endpoint requires an API key.")
        }
        XCTAssertThrowsError(try AISettingsService.addProvider(name: "openrouter", baseURL: "https://a.example.com/v1",
                                                               requiresAPIKey: false, apiKey: "")) {
            XCTAssertEqual(self.message(of: $0), "Another provider already uses the name \"openrouter\".")
        }

        let added = try AISettingsService.addProvider(name: "Local LM", baseURL: "http://localhost:1234/v1/chat/completions",
                                                      requiresAPIKey: false, apiKey: "")
        let entry = try XCTUnwrap(added.providers.first { $0.name == "Local LM" })
        XCTAssertEqual(entry.baseURL, "http://localhost:1234/v1", "the trailing /chat/completions is stripped")
        XCTAssertEqual(entry.popupTitle, "Local LM  (custom)")
        XCTAssertEqual(entry.tableKey, "none")
        XCTAssertEqual(added.status, "Saved Local LM.")
        XCTAssertEqual(added.level, "success")

        let renamed = try AISettingsService.updateProvider(id: entry.id, name: "Renamed LM",
                                                           baseURL: "https://lm.example.com/v1",
                                                           requiresAPIKey: true, apiKey: "secret")
        let updated = try XCTUnwrap(renamed.providers.first { $0.id == entry.id })
        XCTAssertEqual(updated.name, "Renamed LM")
        XCTAssertEqual(updated.tableKey, "required")

        XCTAssertThrowsError(try AISettingsService.updateProvider(id: "builtin.openrouter", name: "X",
                                                                  baseURL: "https://a.example.com/v1",
                                                                  requiresAPIKey: true, apiKey: "k")) {
            XCTAssertEqual(self.message(of: $0), "The built-in providers cannot be edited here.")
        }
        XCTAssertThrowsError(try AISettingsService.deleteProvider(id: "builtin.ollama")) {
            XCTAssertEqual(self.message(of: $0), "The built-in providers cannot be removed.")
        }

        let removed = try AISettingsService.deleteProvider(id: entry.id)
        XCTAssertFalse(removed.providers.contains { $0.id == entry.id })
        XCTAssertEqual(removed.status, "Removed Renamed LM.")
        XCTAssertNil(UserDefaults.standard.string(forKey: "AI.\(entry.id).apiKey"))
    }

    func testPromptsRoundTripThroughExportAndImport() throws {
        try assertLibraryIsIsolated()
        let title = "Unit prompt \(UUID().uuidString)"
        let added = try AISettingsService.addPrompt(title: title, promptText: "  check bounds  ")
        let prompt = try XCTUnwrap(added.prompts.first { $0.title == title })
        XCTAssertEqual(prompt.promptText, "check bounds")

        let exported = AISettingsService.exportPrompts()
        XCTAssertEqual(exported.fileName, "KarmaPro-Prompts.json")

        _ = try AISettingsService.deletePrompt(id: prompt.id)
        let reimported = try AISettingsService.importPrompts(data: exported.data)
        XCTAssertEqual(reimported.added, 1)
        XCTAssertTrue(AISettingsService.prompts().contains { $0.title == title })

        let again = try AISettingsService.importPrompts(data: exported.data)
        XCTAssertEqual(again.added, 0)
        XCTAssertGreaterThanOrEqual(again.skipped, 1)

        XCTAssertThrowsError(try AISettingsService.importPrompts(data: Data("{}".utf8))) {
            XCTAssertEqual(self.message(of: $0), "Import failed: the file is not a valid Karma Pro prompts export.")
        }
        if let copy = AISettingsService.prompts().first(where: { $0.title == title }) {
            _ = try AISettingsService.deletePrompt(id: copy.id)
        }
    }

    func testUpdatePersistsTheModelAndKeyWithoutTouchingTheNetwork() throws {
        try assertLibraryIsIsolated()
        preserveDefaults(["AI.builtin.openrouter.model", "AI.builtin.openrouter.apiKey", "AI.providerID"])

        let client = OpenRouterClient.shared
        let providerID = client.providerID
        // Same provider: no refresh job is started, so nothing reaches the network.
        let update = try AISettingsService.update(providerID: providerID, model: "unit/model", apiKey: " key-1 ")
        XCTAssertNil(update.refreshJobID)
        XCTAssertEqual(update.settings.selectedModel, "unit/model")
        XCTAssertTrue(update.settings.models.contains("unit/model"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "AI.\(providerID).model"), "unit/model")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "AI.\(providerID).apiKey"), "key-1")
        XCTAssertEqual(AISettingsService.state().apiKey, "key-1")

        XCTAssertThrowsError(try AISettingsService.update(providerID: "no-such-provider")) {
            XCTAssertEqual(self.message(of: $0), "No provider with id no-such-provider.")
        }
    }

    // MARK: - Update

    func testSetAutomaticTogglesTheStateAndPostsAnEvent() throws {
        try assertLibraryIsIsolated()
        preserveDefaults(["autoCheckEnabled", "lastCheckDate", "lastKnownVersion", "lastKnownURL"])
        // A check was attempted just now, so the daily gate is closed and no request is made.
        UpdateSettings.lastCheckDate = Date()
        UpdateSettings.automaticChecksEnabled = false

        let lock = NSLock()
        var seen: [UpdateService.UpdateStateDTO] = []
        let subscription = KarmaEventBus.shared.subscribe { type, data in
            guard type == "update.changed",
                  let state = try? KarmaJSON.decoder.decode(UpdateService.UpdateStateDTO.self, from: data) else { return }
            lock.lock()
            seen.append(state)
            lock.unlock()
        }
        defer { KarmaEventBus.shared.unsubscribe(subscription) }

        UpdateService.setAutomatic(true)
        XCTAssertTrue(UpdateService.state().automaticChecks)
        UpdateService.setAutomatic(false)
        XCTAssertFalse(UpdateService.state().automaticChecks)

        lock.lock()
        let automaticValues = seen.map(\.automaticChecks)
        lock.unlock()
        XCTAssertEqual(automaticValues, [true, false])

        XCTAssertThrowsError(try UpdateService.check(manual: false)) {
            XCTAssertEqual(self.message(of: $0), "Automatic checks are off, or no check is due yet.")
        }
    }

    // MARK: - Debugger

    private static let simSource = """
        int helper(int x) {
            int y = x + 1;
            return y;
        }
        int add_twice(int a, int b) {
            int sum = a + b;
            int twice = sum * 2;
            return twice;
        }
        int caller(int n) {
            int r = helper(n);
            return r;
        }
        """

    func testDebuggerStepsBackAndResets() throws {
        try assertLibraryIsIsolated()
        let dir = try makeTemporaryDirectory()
        try writeFiles(["sim.c": Self.simSource], under: dir)
        let path = dir.appendingPathComponent("sim.c").path

        let loaded = try SimDebugService.shared.load(path: path, function: "add_twice")
        XCTAssertTrue(loaded.loaded)
        XCTAssertEqual(loaded.functionName, "add_twice")
        XCTAssertEqual(loaded.parameters.map(\.name), ["a", "b"])
        XCTAssertEqual(loaded.stepCount, 0)
        let startLine = loaded.currentLine
        XCTAssertGreaterThan(startLine, 0)

        var lines = [startLine]
        var last = loaded
        for _ in 0..<3 {
            last = try SimDebugService.shared.step(mode: "over")
            lines.append(last.currentLine)
        }
        XCTAssertEqual(last.stepCount, 3)
        XCTAssertTrue(last.canStepOver)
        XCTAssertGreaterThan(Set(lines).count, 1, "stepping over moves through the function")

        let back = try SimDebugService.shared.step(mode: "back")
        XCTAssertEqual(back.stepCount, 2, "stepping back removes the last step")
        XCTAssertEqual(back.currentLine, lines[2], "stepping back shows the line before the last step")

        let reset = SimDebugService.shared.reset()
        XCTAssertEqual(reset.currentLine, startLine)
        XCTAssertEqual(reset.stepCount, 0)

        let edited = try SimDebugService.shared.setParameter(index: 0, text: "7")
        XCTAssertEqual(edited.parameters[0].value, "7")
        XCTAssertThrowsError(try SimDebugService.shared.setParameter(index: 9, text: "1"))
        _ = SimDebugService.shared.reset()
    }

    func testDebuggerStepIntoEntersACalledFunction() throws {
        try assertLibraryIsIsolated()
        let dir = try makeTemporaryDirectory()
        let source = """
            int square(int v) {
                int r = v * v;
                return r;
            }
            int calc(int a, int b) {
                int s = a + b;
                int q = square(s);
                for (int i = 0; i < 3; i++) {
                    q = q + i;
                }
                return q;
            }
            """
        try writeFiles(["sim.c": source], under: dir)
        let path = dir.appendingPathComponent("sim.c").path

        _ = try KarmaWorkspace.shared.open(root: dir.path)
        waitUntil("the source index", { KarmaWorkspace.shared.read { $0.sourceIndex != nil } })
        let loaded = try SimDebugService.shared.load(path: path, function: "calc")
        XCTAssertEqual(loaded.selectedFrameIndex, 0)
        XCTAssertEqual(loaded.frames.filter(\.isSelected).map(\.index), [0])
        let beforeInto = try SimDebugService.shared.step(mode: "over")
        let into = try SimDebugService.shared.step(mode: "into")
        XCTAssertEqual(into.stepCount, beforeInto.stepCount + 1)
        XCTAssertNotEqual(into.currentLine, beforeInto.currentLine, "step into moves to another line")
        let callee = try SimDebugService.shared.step(mode: "into")
        XCTAssertEqual(callee.badge, "square()")
        XCTAssertEqual(callee.statusText, "r = 10000")
        XCTAssertEqual(callee.frames.map(\.functionName), ["calc", "square"])
        XCTAssertEqual(callee.frames.filter(\.isActive).map(\.index), [1])
        XCTAssertEqual(callee.selectedFrameIndex, 0)
        XCTAssertEqual(callee.frames.filter(\.isSelected).map(\.index), [0])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: callee.watchRows.map { ($0.name, $0.value) }),
                       ["a": "50", "b": "50", "s": "100", "q": "nil"])

        let selected = try SimDebugService.shared.selectFrame(index: 1)
        XCTAssertEqual(selected.selectedFrameIndex, 1)
        XCTAssertEqual(selected.frames.filter(\.isSelected).map(\.index), [1])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: selected.watchRows.map { ($0.name, $0.value) }),
                       ["v": "100", "r": "10000"])
        XCTAssertEqual(selected.badge, callee.badge)
        XCTAssertEqual(selected.statusText, callee.statusText)
        let unchanged = SimDebugService.shared.state()
        XCTAssertEqual(unchanged.selectedFrameIndex, 1)
        XCTAssertEqual(unchanged.watchRows.map(\.name), selected.watchRows.map(\.name))
        XCTAssertEqual(unchanged.watchRows.map(\.value), selected.watchRows.map(\.value))

        let next = try SimDebugService.shared.step(mode: "into")
        XCTAssertEqual(next.selectedFrameIndex, 0)
        XCTAssertEqual(next.frames.filter(\.isSelected).map(\.index), [0])
        let reset = SimDebugService.shared.reset()
        XCTAssertEqual(reset.selectedFrameIndex, 0)
        XCTAssertEqual(reset.frames.filter(\.isSelected).map(\.index), [0])
    }

    // MARK: - Entry points

    private static let serverSource = """
        #include <sys/socket.h>
        #include <stdio.h>
        void handle(int fd) {
            char buf[128];
            recv(fd, buf, sizeof buf, 0);
            printf("%s", buf);
        }
        int main(int argc, char **argv) {
            char line[64];
            fgets(line, sizeof line, stdin);
            return 0;
        }
        """

    func testEntryPointsFindsPrimaryEntriesAndTracesAnInlineSite() throws {
        try assertLibraryIsIsolated()
        let project = try makeTemporaryDirectory()
        try writeFiles(["server.c": Self.serverSource], under: project)
        _ = try KarmaWorkspace.shared.open(root: project.path)

        let state = try result(EntryPointsService.EntryPointsStateDTO.self,
                               job: try EntryPointsService.shared.start())
        XCTAssertFalse(state.busy)
        XCTAssertFalse(state.indirectEnabled)
        let sites = state.groups.flatMap(\.sites)
        let recv = try XCTUnwrap(sites.first { $0.apiName == "recv" }, "recv is a remote entry point")
        XCTAssertEqual(recv.origin, "internet")
        XCTAssertEqual(recv.confidence, "primary")
        XCTAssertEqual(recv.relativePath, "server.c")
        XCTAssertEqual(recv.entryVariable, "buf", "recv writes into buf, which is traced")
        XCTAssertTrue(sites.contains { $0.apiName == "fgets" && $0.origin == "local" })

        let traced = try result(EntryPointsService.EntryTraceDTO.self,
                                job: try EntryPointsService.shared.trace(siteID: recv.id))
        XCTAssertEqual(traced.originLabel, "Remote")
        XCTAssertEqual(traced.nodes.first?.name, "Remote")
        XCTAssertEqual(traced.nodes.first?.isOrigin, true)
        let start = try XCTUnwrap(traced.nodes.first { $0.isStart })
        XCTAssertEqual(start.name, "handle")
        XCTAssertEqual(start.line, recv.line)
        XCTAssertEqual(traced.edges.first, EntryPointsService.EntryTraceEdgeDTO(from: "Remote", to: "handle"))
        XCTAssertEqual(EntryPointsService.shared.state().trace?.siteID, recv.id)
    }
}
