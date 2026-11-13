// by cipher.org.uk
import AppKit

/// Shows what a pull request actually changed, line by line.
///
/// The scanner is diff-aware in the sense that a finding is only attributed to a
/// pull request when it falls inside a changed hunk, and that the review tree
/// is pruned to the changed files. Neither of those is visible to the user: a
/// file marked "modified" with a line range says nothing about whether the new
/// code is safe. This window is the missing half, showing the added and removed
/// lines with three lines of context, additions and removals coloured, and the
/// diff of every changed file selectable in one place.
final class PRDiffWindowController: NSWindowController {
    private let textView = NSTextView()
    private let filePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let summaryLabel = NSTextField(labelWithString: "")
    private var files: [ChangedFile] = []

    /// Shown when a file is picked, so the path survives being scrolled away.
    var onOpenFile: ((URL) -> Void)?

    convenience init() {
        let window = EscClosableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Pull Request Changes"
        window.minSize = NSSize(width: 560, height: 320)
        // Centred on the screen the app is on rather than left wherever the
        // content rect happened to be, which put the window in the top-left of
        // the primary display and partly off smaller ones.
        window.center()
        self.init(window: window)
        build()
    }

    private func build() {
        guard let content = window?.contentView else { return }

        filePopUp.target = self
        filePopUp.action = #selector(fileChanged)
        filePopUp.controlSize = .regular
        filePopUp.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSStackView(views: [filePopUp, summaryLabel])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.alignment = .centerY
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    /// Loads a pull request's changed files. Called once per review, before the
    /// window is shown, so the first paint is already the real diff.
    func load(files: [ChangedFile], repoRoot: URL) {
        self.files = files

        filePopUp.removeAllItems()
        for file in files.filter({ $0.kind != .deleted }) {
            let suffix = file.kind == .added ? " (added)" : ""
            filePopUp.addItem(withTitle: "\(file.kind.badge)  \(file.path)\(suffix)")
        }
        if filePopUp.numberOfItems == 0 {
            filePopUp.addItem(withTitle: "No reviewable changes")
        }
        show(index: 0, repoRoot: repoRoot)
    }

    @objc private func fileChanged() {
        show(index: max(filePopUp.indexOfSelectedItem, 0), repoRoot: rootURL)
    }

    private var rootURL: URL?

    private func show(index: Int, repoRoot: URL?) {
        rootURL = repoRoot
        let reviewable = files.filter { $0.kind != .deleted }
        guard index < reviewable.count else {
            textView.string = "This pull request has no reviewable file changes."
            summaryLabel.stringValue = ""
            return
        }
        let file = reviewable[index]
        textView.textStorage?.setAttributedString(highlighted(file.patch))
        summaryLabel.stringValue = PRDiffSummary.summary(for: file)
        if let repoRoot = repoRoot {
            onOpenFile?(repoRoot.appendingPathComponent(file.path))
        }
    }

    /// Colours the patch. Removals red, additions green, file headers bold, and
    /// anything the heuristic considers worth a user look is marked so the
    /// reader is pointed at it rather than left to read every line.
    private func highlighted(_ patch: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let base = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            var attributes: [NSAttributedString.Key: Any] = [.font: base]
            var text = line

            if line.hasPrefix("@@") {
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            } else if line.hasPrefix("+") {
                attributes[.foregroundColor] = NSColor.systemGreen
            } else if line.hasPrefix("-") {
                attributes[.foregroundColor] = NSColor.systemRed
            } else if line.hasPrefix("index ") || line.hasPrefix("Binary ") {
                attributes[.foregroundColor] = NSColor.tertiaryLabelColor
            }

            // Highlight the specific additions that change what the code does.
            if line.hasPrefix("+"), SuspiciousLine.isSuspicious(String(line.dropFirst())) {
                attributes[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.28)
                attributes[.font] = bold
            }
            text += "\n"
            output.append(NSAttributedString(string: text, attributes: attributes))
        }
        return output
    }
}
