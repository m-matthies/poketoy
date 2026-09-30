import AppKit
import PokeToyCore

/// End-of-round summary: score, best score, and which catches to keep as pets.
@MainActor
final class ResultsWindowController: NSWindowController {
    private unowned let model: AppModel
    private let results: CatchResults
    private var checkboxes: [NSButton] = []
    /// Portrait icons next to the catches, filled in as they load.
    private var icons: [NSImageView] = []
    private let keepable: Int
    private var keepButton: NSButton!
    private var releaseButton: NSButton!

    init(model: AppModel, results: CatchResults, best: Int, isNewBest: Bool, keepable: Int) {
        self.model = model
        self.results = results
        self.keepable = keepable
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 220), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Catch Results"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        var rows: [NSView] = []
        let headline = NSTextField(labelWithString: "Score: \(results.score)")
        headline.font = .boldSystemFont(ofSize: 22)
        rows.append(headline)
        rows.append(NSTextField(labelWithString: isNewBest ? "New best score!" : "Best: \(best)"))
        if results.catches.isEmpty {
            rows.append(NSTextField(labelWithString: "Nothing caught this time."))
        } else {
            rows.append(NSTextField(labelWithString: "Caught — tick the ones you want to keep as pets:"))
            for record in results.catches {
                let title = record.isShiny ? "✦ \(record.displayName) (Shiny)" : record.displayName
                // Nothing is kept unless ticked.
                let box = NSButton(checkboxWithTitle: title, target: self, action: #selector(tickChanged))
                box.state = .off
                checkboxes.append(box)
                let icon = NSImageView(image: NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: nil) ?? NSImage())
                icon.imageScaling = .scaleProportionallyUpOrDown
                icon.contentTintColor = .tertiaryLabelColor
                icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
                icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
                icons.append(icon)
                let row = NSStackView(views: [box, icon])
                row.orientation = .horizontal
                row.spacing = 6
                rows.append(row)
            }
            if keepable < results.catches.count {
                let room = keepable == 0 ? "You have no room for more pets" : "You can keep \(keepable) of them"
                rows.append(NSTextField(labelWithString: "\(room) (limit \(Playground.maxOwnPets) pets; "
                                        + "pets in their Poké Balls count too)."))
            }
        }
        let keep = NSButton(title: results.catches.isEmpty ? "OK" : "Keep Selected", target: self, action: #selector(keepSelected))
        let release = NSButton(title: "Release All", target: self, action: #selector(releaseAll))
        release.isHidden = results.catches.isEmpty
        keepButton = keep
        releaseButton = release
        updateChoice()
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
        loadIcons()
    }

    /// Fetches each catch's portrait (the shiny form's own if SpriteCollab has one, else its species').
    private func loadIcons() {
        for (index, record) in results.catches.enumerated() {
            Task {
                guard let url = await model.portrait(forCatch: record.path), let image = NSImage(contentsOf: url) else { return }
                icons[index].image = image
                icons[index].contentTintColor = nil
            }
        }
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

    private var ticked: Set<Int> {
        Set(checkboxes.indices.filter { checkboxes[$0].state == .on })
    }

    @objc private func tickChanged() {
        updateChoice()
    }

    /// Keeps the boxes within the pet limit, and the buttons in step: Return keeps what's ticked, or releases all.
    private func updateChoice() {
        let ticked = self.ticked
        for (box, allowed) in zip(checkboxes, CatchGame.tickable(ticked: ticked, count: checkboxes.count, keepable: keepable)) {
            box.isEnabled = allowed
        }
        guard !results.catches.isEmpty else {
            keepButton.keyEquivalent = "\r"
            return
        }
        keepButton.title = ticked.isEmpty ? "Keep Selected" : ticked.count == 1 ? "Keep 1 Pokémon" : "Keep \(ticked.count) Pokémon"
        keepButton.isEnabled = !ticked.isEmpty
        keepButton.keyEquivalent = ticked.isEmpty ? "" : "\r"
        releaseButton.keyEquivalent = ticked.isEmpty ? "\r" : ""
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
