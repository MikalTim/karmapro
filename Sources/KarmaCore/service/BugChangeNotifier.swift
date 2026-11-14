// by cipher.org.uk
import Foundation

/// Turns the bug store's change notification into the `bugs.changed` event, as `AppDelegate` turns it into the
/// Dock badge. A front end calls `start()` once at launch.
public enum BugChangeNotifier {
    private static let lock = NSLock()
    private static var observer: NSObjectProtocol?

    public static func start() {
        lock.lock()
        defer { lock.unlock() }
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .bugStoreDidChange, object: nil, queue: nil) { _ in
            KarmaEventBus.shared.post("bugs.changed", BugsChangedEvent(openCount: BugStore.shared.openBugCount))
        }
    }
}
