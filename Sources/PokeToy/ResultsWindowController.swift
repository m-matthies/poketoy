import AppKit
import PokeToyCore

/// End-of-round summary: score, best score, and which catches to keep as pets.
@MainActor
final class ResultsWindowController: NSWindowController {
    private unowned let model: AppModel
    private let results: CatchResults
    private var checkboxes: [NSButton] = []

    init(model: AppModel, results: CatchResults, best: Int, isNewBest: Bool, keepable: Int, daily: Bool) {
        self.model = model
        self.results = results
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 220), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Catch Results"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        var rows: [NSView] = []
        let headline = NSTextField(labelWithString: "Score: \(results.score)")
        headline.font = .boldSystemFont(ofSize: 22)
        rows.append(headline)
        let bestLabel = daily ? "Daily best" : "Best"
        rows.append(NSTextField(labelWithString: isNewBest ? "New \(bestLabel.lowercased()) score!" : "\(bestLabel): \(best)"))
        if results.catches.isEmpty {
            rows.append(NSTextField(labelWithString: "Nothing caught this time."))
        } else {
            rows.append(NSTextField(labelWithString: "Caught — tick the ones to keep as pets:"))
            for (index, record) in results.catches.enumerated() {
                let title = record.isShiny ? "✦ \(record.displayName) (Shiny)" : record.displayName
                let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
                box.state = index < keepable ? .on : .off
                box.isEnabled = index < keepable
                checkboxes.append(box)
                rows.append(box)
            }
            if keepable < results.catches.count {
                rows.append(NSTextField(labelWithString: "You can keep \(keepable) more (limit \(Playground.maxOwnPets) pets)."))
            }
        }
        let keep = NSButton(title: results.catches.isEmpty ? "OK" : "Keep Selected", target: self, action: #selector(keepSelected))
        keep.keyEquivalent = "\r"
        let release = NSButton(title: "Release All", target: self, action: #selector(releaseAll))
        release.isHidden = results.catches.isEmpty
        let buttons = NSStackView(views: [release, keep])
        buttons.orientation = .horizontal
        rows.append(buttons)

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.setContentSize(stack.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Sprite paths of this round's catches.
    var catchPaths: [String] { results.catches.map(\.path) }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func keepSelected() {
        let kept = zip(results.catches, checkboxes).filter { $0.1.state == .on }.map(\.0)
        model.keepCatches(kept)
        close()
    }

    @objc private func releaseAll() {
        close()
    }
}
