// by cipher.org.uk
import Foundation

/// The queue on which engine callbacks that the AppKit app expects on the
/// main thread are delivered: the pull-request poller, review scans, update
/// checks and the end of an AI stream.
///
/// The AppKit app leaves this as the main queue. A front end without a UI
/// thread (the web server) sets a queue of its own once at startup, before any
/// of those features is used.
public enum KarmaCallbackQueue {
    public static var queue: DispatchQueue = .main
}
