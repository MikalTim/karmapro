// by cipher.org.uk
import Foundation
import AppKit

/// Window controller that scans a project directory for license files (LICENSE, LICENSE.md,
/// COPYING, etc.), identifies their license type, and evaluates commercial use permit and
/// required license terms.
final class LicensingWindowController: NSWindowController {
    private var textView: NSTextView!

    convenience init(projectRoot: URL?) {
        let window = EscClosableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Project License & Commercial Use Auditor"
        window.center()
        self.init(window: window)
        setupUI()
        scanLicenses(in: projectRoot)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView(frame: contentView.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let tv = NSTextView(frame: scrollView.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)
        tv.textContainerInset = NSSize(width: 15, height: 15)
        tv.backgroundColor = NSColor.textBackgroundColor

        scrollView.documentView = tv
        contentView.addSubview(scrollView)
        self.textView = tv
    }

    private func scanLicenses(in root: URL?) {
        textView.string = LicenseScanner.report(root: root)
    }
}
