import AppKit
import PokeToyCore

/// A new player's first choice: Pikachu, Charmander, Squirtle or Bulbasaur.
@MainActor
final class StarterWindowController: NSWindowController {
    private unowned let model: AppModel
    private var buttons: [NSButton] = []
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 240), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Choose Your First Pokémon"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let headline = NSTextField(labelWithString: "Which Pokémon will be your first partner?")
        headline.font = .boldSystemFont(ofSize: 15)
        let hint = NSTextField(labelWithString: "Catch more in the Catch Game.")
        hint.textColor = .secondaryLabelColor
        for (index, starter) in Starters.all.enumerated() {
            let button = NSButton(title: starter.displayName, target: self, action: #selector(choose(_:)))
            button.tag = index
            button.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
            button.imagePosition = .imageAbove
            button.imageScaling = .scaleProportionallyUpOrDown
            button.bezelStyle = .regularSquare
            button.widthAnchor.constraint(equalToConstant: 100).isActive = true
            button.heightAnchor.constraint(equalToConstant: 110).isActive = true
            buttons.append(button)
        }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 12
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        let footer = NSStackView(views: [spinner, status])
        footer.orientation = .horizontal

        let stack = NSStackView(views: [headline, hint, row, footer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
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

    func show() {
        setBusy(false)
        status.stringValue = ""
        loadPortraits()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func loadPortraits() {
        for (index, starter) in Starters.all.enumerated() {
            Task {
                guard let url = await model.normalPortrait(for: starter.path), let image = NSImage(contentsOf: url) else { return }
                buttons[index].image = image
            }
        }
    }

    @objc private func choose(_ sender: NSButton) {
        let starter = Starters.all[sender.tag]
        setBusy(true)
        status.stringValue = "Getting \(starter.displayName) ready…"
        Task {
            do {
                try await model.chooseStarter(starter)
                close()
            } catch {
                setBusy(false)
                status.stringValue = "Couldn't download \(starter.displayName) — check your connection and try again."
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        for button in buttons { button.isEnabled = !busy }
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
}
