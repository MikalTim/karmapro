// by cipher.org.uk
import AppKit

/// A lightweight syntax highlighter that colors a source string into an
/// attributed string. Supports a small set of common languages via keywords.
/// Finding the spans is `SyntaxTokenizer`'s job (in KarmaCore, shared with the
/// web front end); this type only turns them into colours.
public struct SyntaxHighlighter {

    /// Theme colors for keywords, comments, strings, etc.
    public struct Colors {
        public var keyword: NSColor
        public var string: NSColor
        public var comment: NSColor
        public var number: NSColor
        public var type: NSColor
        public var identifier: NSColor
        public var plain: NSColor

        public init(
            keyword: NSColor? = nil,
            string: NSColor? = nil,
            comment: NSColor? = nil,
            number: NSColor? = nil,
            type: NSColor? = nil,
            identifier: NSColor? = nil,
            plain: NSColor? = nil
        ) {
            self.keyword = keyword ?? Colors.adaptive(light: (0.60, 0.23, 0.90), dark: (0.78, 0.58, 1.00))
            self.string = string ?? Colors.adaptive(light: (0.10, 0.48, 0.12), dark: (0.62, 0.86, 0.45))
            self.comment = comment ?? Colors.adaptive(light: (0.40, 0.42, 0.46), dark: (0.50, 0.54, 0.60))
            self.number = number ?? Colors.adaptive(light: (0.80, 0.42, 0.05), dark: (0.94, 0.68, 0.36))
            self.type = type ?? Colors.adaptive(light: (0.00, 0.40, 0.72), dark: (0.49, 0.80, 1.00))
            self.identifier = identifier ?? Colors.adaptive(light: (0.13, 0.14, 0.16), dark: (0.90, 0.90, 0.90))
            self.plain = plain ?? Colors.adaptive(light: (0.13, 0.14, 0.16), dark: (0.88, 0.88, 0.88))
        }

        /// Builds a dynamic color that resolves to the dark value in dark mode and light in light mode.
        static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
            func toColor(_ c: (CGFloat, CGFloat, CGFloat)) -> NSColor {
                NSColor(calibratedRed: c.0, green: c.1, blue: c.2, alpha: 1)
            }
            return NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark ? toColor(dark) : toColor(light)
            }
        }
    }

    public var colors = Colors()

    public init() {}

    /// Highlights the given source text. Returns nil if the extension is unsupported.
    public func highlight(_ source: String, for ext: String) -> NSAttributedString? {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: colors.plain
        ]

        guard let tokens = SyntaxTokenizer.shared.tokens(for: source, fileExtension: ext) else {
            return NSAttributedString(string: source, attributes: baseAttrs)
        }

        let result = NSMutableAttributedString(string: source, attributes: baseAttrs)
        for (range, kind) in tokens {
            let color: NSColor
            switch kind {
            case .keyword: color = colors.keyword
            case .string: color = colors.string
            case .comment: color = colors.comment
            case .number: color = colors.number
            case .type: color = colors.type
            case .plain: color = colors.plain
            }
            result.addAttribute(.foregroundColor, value: color, range: range)
        }

        return result
    }
}
