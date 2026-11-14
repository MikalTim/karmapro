// by cipher.org.uk
import AppKit

/// Window that shows every place a Java class is instantiated (`new ClassName(...)`)
/// across the opened project, rendered as an animated graph: the class is the central
/// (highlighted) node and each instantiation site is a node below it, with animated
/// dashed edges flowing from the class into each site. Clicking a site node opens
/// that file at the instantiation line in the main source viewer.
final class ClassUsageWindowController: NSWindowController {
    var requestedClass = ""
    private var occurrences: [ClassUsageOccurrence] = []
    /// Maps a graph node name (e.g. "Main.java:5") back to its occurrence.
    private var nodeToOccurrence: [String: ClassUsageOccurrence] = [:]

    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let diagramView = DataFlowDiagramView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")

    /// Fired when the user wants to open a file at a given line in the main viewer.
    var onOpenFile: ((URL, Int) -> Void)?

    convenience init(className: String) {
        let window = EscClosableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Instantiations of \(className)"
        window.minSize = NSSize(width: 560, height: 360)
        self.init(window: window)
        self.requestedClass = className
        buildContent()
    }

    /// Scans the project under `root` for `new <className>(` occurrences and renders
    /// them as an animated graph.
    func load(root: URL) {
        occurrences = ClassUsageScanner.scanInstantiations(of: requestedClass, in: root, isCancelled: { false })
        nodeToOccurrence.removeAll()

        if occurrences.isEmpty {
            diagramView.isHidden = true
            emptyLabel.isHidden = false
            statusLabel.stringValue = "No instantiations of “\(requestedClass)” found."
            return
        }

        emptyLabel.isHidden = true
        diagramView.isHidden = false

        // Build a graph: class node (highlighted) + one node per instantiation site.
        let graph = CallGraph()
        let classNode = requestedClass
        _ = graph.node(for: classNode)

        var layoutEdges: [(String, String)] = [] // site -> class  (for layout ranking, class on top)
        var dataEdges: [(String, String)] = []   // class -> site  (for animated arrows)
        for o in occurrences {
            // Keep node names unique by including the line number.
            let nodeName = "\(o.fileURL.lastPathComponent):\(o.line)"
            var unique = nodeName
            var counter = 1
            while graph.hasNode(unique) {
                counter += 1
                unique = "\(nodeName) (\(counter))"
            }
            _ = graph.node(for: unique)
            nodeToOccurrence[unique] = o
            layoutEdges.append((unique, classNode))
            dataEdges.append((classNode, unique))
        }

        diagramView.animatedOnlyEdges = true
        diagramView.onNodeClick = { [weak self] nodeName in
            guard let self = self else { return }
            if nodeName == classNode { return }
            if let occ = self.nodeToOccurrence[nodeName] {
                self.onOpenFile?(occ.fileURL, occ.line)
            }
        }
        diagramView.display(graph: graph, callEdges: layoutEdges, dataEdges: dataEdges, highlight: classNode)

        statusLabel.stringValue = "\(occurrences.count) instantiation(s) of “\(requestedClass)” — click a node to open it"
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.stringValue = "Where is “\(requestedClass)” instantiated?"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        diagramView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(diagramView)

        emptyLabel.font = NSFont.systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.stringValue = "No instantiations of “\(requestedClass)” found."
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyLabel)
        emptyLabel.isHidden = true

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            diagramView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            diagramView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            diagramView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            diagramView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
    }
}
