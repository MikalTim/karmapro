import Foundation
import XCTest
@testable import KarmaCore

final class BugChangeNotifierTests: XCTestCase {
    func testStoreChangesBecomeBugsChangedEventsWithTheOpenCount() {
        BugChangeNotifier.start()
        BugChangeNotifier.start()
        var events: [String] = []
        let lock = NSLock()
        let token = KarmaEventBus.shared.subscribe { type, data in
            guard type == "bugs.changed" else { return }
            lock.lock(); events.append(String(decoding: data, as: UTF8.self)); lock.unlock()
        }
        defer { KarmaEventBus.shared.unsubscribe(token) }

        NotificationCenter.default.post(name: .bugStoreDidChange, object: nil)

        lock.lock()
        let seen = events
        lock.unlock()
        XCTAssertEqual(seen.count, 1, "starting twice must not post twice")
        XCTAssertTrue(seen[0].hasPrefix("{\"openCount\":"), seen[0])
    }
}
