// by cipher.org.uk
import Foundation
import KarmaCore

/// What `AppDelegate.applicationDidFinishLaunching` does for the macOS app, in its order, for the web server.
func startKarmaServices() {
    // The server has no main run loop: poll results, review scans, update checks and the end of an AI stream
    // are delivered on this queue instead.
    KarmaCallbackQueue.queue = DispatchQueue(label: "app.karmapro.server.callbacks")
    KarmaMCP.installTransport { VaporMCPTransport() }
    KarmaPlatform.installDefaultServices()
    BugChangeNotifier.start()
    PRService.shared.start()
    UpdateService.install()
    KarmaMCP.startIfAutoStart()
}
