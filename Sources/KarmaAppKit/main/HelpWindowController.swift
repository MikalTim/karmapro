// by cipher.org.uk
import Foundation
import WebKit
import AppKit

/// Window controller that displays the Karma Pro User Guide & Help document
/// rendered cleanly in a WebKit view, complete with the splash image and formatting.
final class HelpWindowController: NSWindowController {
    private var webView: WKWebView!

    convenience init() {
        let window = EscClosableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Karma Pro Help & User Guide"
        window.center()
        self.init(window: window)
        setupUI()
        loadHelpContent()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: contentView.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        contentView.addSubview(webView)
    }

    private func loadHelpContent() {
        let mdPath = Bundle.main.path(forResource: "HelpContent", ofType: "md")
            ?? "/Users/manos/visual studio/reviewer/Resources_src/HelpContent.md"
        
        guard let mdContent = try? String(contentsOfFile: mdPath, encoding: .utf8) else {
            webView.loadHTMLString("<h3>Help content not found.</h3>", baseURL: nil)
            return
        }

        let html = HelpMarkdown.page(markdown: mdContent, splashImageSrc: "HelpSplash.jpg")
        let baseURL = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/Users/manos/visual studio/reviewer/Resources_src/")
        webView.loadHTMLString(html, baseURL: baseURL)
    }
}
