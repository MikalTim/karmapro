import Foundation

/// Renders the Karma Pro help document (`HelpContent.md`) as one HTML page.
///
/// The converter is intentionally small: it understands the subset of Markdown
/// the help file uses. AppKit shows the page in a `WKWebView`; the web front end
/// shows the same page in a sandboxed frame.
public enum HelpMarkdown {
    /// Builds the complete HTML page for `markdown`.
    ///
    /// - Parameter splashImageSrc: the `src` of the splash image. The help file's
    ///   `![...](...)` line becomes a centred image with this source. When nil, that
    ///   line produces no output at all.
    public static func page(markdown: String, splashImageSrc: String?) -> String {
        let html = markdownToHTML(markdown, splashImageSrc: splashImageSrc)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                color: #333;
                background-color: #f9f9fb;
                padding: 30px 40px;
                line-height: 1.6;
                font-size: 14px;
            }
            h1 { font-size: 24px; color: #111; border-bottom: 2px solid #eaeaea; padding-bottom: 8px; margin-top: 0; }
            h2 { font-size: 16px; color: #222; margin-top: 25px; border-bottom: 1px solid #eaeaea; padding-bottom: 4px; }
            p { margin: 8px 0; }
            ul { margin: 6px 0 12px 20px; }
            li { margin-bottom: 4px; }
            code { background: #eee; padding: 2px 6px; border-radius: 4px; font-size: 13px; font-family: monospace; }
            strong { color: #111; }
            hr { border: none; border-top: 1px solid #eaeaea; margin: 25px 0; }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }

    private static func markdownToHTML(_ md: String, splashImageSrc: String?) -> String {
        // Basic Markdown to HTML converter with styling
        let escaped = md
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        var html = ""
        let lines = escaped.components(separatedBy: "\n")
        var inList = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                if inList { html += "</ul>"; inList = false }
                html += "<h1>\(String(trimmed.dropFirst(2)))</h1>\n"
            } else if trimmed.hasPrefix("## ") {
                if inList { html += "</ul>"; inList = false }
                html += "<h2>\(String(trimmed.dropFirst(3)))</h2>\n"
            } else if trimmed.hasPrefix("- ") {
                if !inList { html += "<ul>"; inList = true }
                let item = String(trimmed.dropFirst(2))
                html += "<li>\(formatInline(item))</li>\n"
            } else if trimmed.hasPrefix("1. ") || trimmed.hasPrefix("2. ") || trimmed.hasPrefix("3. ") || trimmed.hasPrefix("4. ") || trimmed.hasPrefix("5. ") || trimmed.hasPrefix("6. ") {
                if inList { html += "</ul>"; inList = false }
                html += "<p><strong>\(trimmed)</strong></p>\n"
            } else if trimmed.hasPrefix("![Karma Pro Splash]") || trimmed.hasPrefix("![") && trimmed.contains("](") {
                if inList { html += "</ul>"; inList = false }
                if let splashImageSrc {
                    html += "<div style='text-align:center; margin: 20px 0;'><img src='\(splashImageSrc)' style='max-width:320px; border-radius:8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);'/></div>\n"
                }
            } else if trimmed.isEmpty {
                if inList { html += "</ul>"; inList = false }
                html += "<br/>\n"
            } else {
                if inList { html += "</ul>"; inList = false }
                html += "<p>\(formatInline(trimmed))</p>\n"
            }
        }
        if inList { html += "</ul>" }

        return html
    }

    private static func formatInline(_ text: String) -> String {
        // Convert **bold** to <strong>
        var res = text
        while let start = res.range(of: "**"), let end = res.range(of: "**", range: start.upperBound..<res.endIndex) {
            let boldText = res[start.upperBound..<end.lowerBound]
            res.replaceSubrange(start.lowerBound..<end.upperBound, with: "<strong>\(boldText)</strong>")
        }
        return res
    }
}
