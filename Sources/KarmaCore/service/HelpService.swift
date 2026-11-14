// by cipher.org.uk
import Foundation

/// The Karma Pro Help window (`HelpWindowController`): the bundled user guide,
/// rendered to one HTML page.
public enum HelpService {
    /// The image source the help page uses for its splash picture. The web server serves it from `/api/resources/`.
    static let splashImageSrc = "/api/resources/HelpSplash.jpg"

    /// The window's text when the help file cannot be read.
    static let notFoundHTML = "<h3>Help content not found.</h3>"

    /// `GET /api/help`: the complete help page as HTML.
    public static func html() -> String {
        guard let url = KarmaResources.url(forResource: "HelpContent", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8)
        else { return notFoundHTML }
        return HelpMarkdown.page(markdown: markdown, splashImageSrc: splashImageSrc)
    }
}
