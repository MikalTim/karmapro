import Foundation
import XCTest
@testable import KarmaCore

/// The AI Assistant window's rules that need no model: what Send, Continue and New Chat do when there is nothing to send.
final class AIChatServiceTests: XCTestCase {

    func testSendingAnEmptyPromptShowsTheHintAndStartsNothing() {
        let service = AIChatService()

        let state = service.send(text: "  \n ")

        XCTAssertEqual(state.status, "Type or paste a prompt first.")
        XCTAssertEqual(state.statusLevel, "error")
        XCTAssertFalse(state.requestInFlight)
        XCTAssertEqual(state.sendTitle, "Send to AI")
        XCTAssertTrue(state.transcript.isEmpty)
    }

    func testContinueWithoutAnInterruptedTaskChangesNothing() {
        let service = AIChatService()
        let before = service.state()

        let after = service.continueTurn()

        XCTAssertEqual(after.seq, before.seq)
        XCTAssertFalse(after.canContinue)
        XCTAssertTrue(after.transcript.isEmpty)
    }

    func testNewChatClearsTheStatusMessageAndStopIsHarmlessWhenIdle() {
        let service = AIChatService()
        _ = service.send(text: "")

        let cleared = service.newChat()

        XCTAssertEqual(cleared.status, "New conversation \u{2014} the previous context was cleared.")
        XCTAssertEqual(cleared.statusLevel, "info")
        XCTAssertEqual(service.stop().status, cleared.status)
    }

    func testStatusChangesArePostedAsStreamEventsWithRisingNumbers() {
        let service = AIChatService()
        var events: [String] = []
        let lock = NSLock()
        let token = KarmaEventBus.shared.subscribe { type, data in
            guard type == "ai.stream" else { return }
            lock.lock(); events.append(String(decoding: data, as: UTF8.self)); lock.unlock()
        }
        defer { KarmaEventBus.shared.unsubscribe(token) }

        _ = service.send(text: "")
        _ = service.newChat()

        lock.lock()
        let seen = events
        lock.unlock()
        XCTAssertEqual(seen.count, 3)
        XCTAssertTrue(seen[0].contains("\"seq\":1") && seen[0].contains("Type or paste a prompt first."))
        XCTAssertTrue(seen[1].contains("\"seq\":2") && seen[1].contains("New conversation"))
        XCTAssertTrue(seen[2].contains("\"seq\":3") && seen[2].contains("turnFinished"))
    }
}
