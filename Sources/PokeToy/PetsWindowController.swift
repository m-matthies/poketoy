import AppKit
import PokeToyCore

/// Your pets: rename them and see how they're doing.
@MainActor
final class PetsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private unowned let model: AppModel
    private var pets: [PetRecord] = []
    private var portraits: [String: NSImage] = [:]
    private var requestedPortraits: Set<String> = []
    private let header = NSTextField(labelWithString: "")
    private let table = ClickToEditTableView()
    /// A refresh was skipped while a name was being typed; catch up when typing ends.
    private var needsReload = false
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Pets"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 240)
        super.init(window: window)

        header.font = .boldSystemFont(ofSize: 15)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pet"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 84
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        let stack = NSStackView(views: [header, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ])
        window.center()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshIfVisible() }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        reload()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshIfVisible() {
        guard let window, window.isVisible || window.isMiniaturized else { return }
        // Don't pull the rug out from under a name being typed: catch up afterwards.
        if isEditing {
            needsReload = true
            return
        }
        reload()
    }

    private var isEditing: Bool { window?.firstResponder is NSTextView }

    private func reload() {
        needsReload = false
        pets = model.settings.pets
        header.stringValue = pets.isEmpty ? "No pets yet — catch some in the Catch Game!"
            : "\(pets.count) of \(Playground.maxOwnPets) pets · \(model.petsOnScreen) out, "
              + "\(pets.count - model.petsOnScreen) in their Poké Balls"
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        pets.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let pet = pets[row]
        let cell = (tableView.makeView(withIdentifier: PetCell.identifier, owner: nil) as? PetCell) ?? PetCell()
        loadPortrait(pet.spritePath)
        cell.portrait.image = portraits[pet.spritePath]
        cell.name.stringValue = pet.name
        cell.name.placeholderString = pet.displayName
        cell.name.tag = row
        cell.name.delegate = self
        let species = (pet.isShiny ? "✦ " : "") + pet.displayName.replacingOccurrences(of: " (Shiny)", with: "")
            + (pet.nickname == nil ? "" : " · named by you")
        cell.species.stringValue = species
        cell.stats.stringValue = stats(of: pet)
        cell.release.tag = row
        cell.release.target = self
        cell.release.action = #selector(release(_:))
        cell.ball.title = pet.inBall ? "Let Out" : "Return to Ball"
        cell.ball.tag = row
        cell.ball.target = self
        cell.ball.action = #selector(toggleBall(_:))
        cell.portrait.alphaValue = pet.inBall ? 0.45 : 1
        return cell
    }

    private func stats(of pet: PetRecord) -> String {
        var lines: [String] = []
        var first: [String] = []
        if let joined = pet.joined { first.append("Together since \(dateFormatter.string(from: joined))") }
        first.append(pet.treatsEaten == 1 ? "1 treat eaten" : "\(pet.treatsEaten) treats eaten")
        first.append(pet.focusSessions == 1 ? "1 focus session" : "\(pet.focusSessions) focus sessions")
        lines.append(first.joined(separator: " · "))
        var second: [String] = []
        second.append(model.bestFriendName(of: pet.id).map { "Best friend: \($0)" } ?? "No best friend yet")
        switch model.evolutionStatus(of: pet.id) {
        case .ready(let options):
            second.append("Ready to evolve into " + options.map(\.displayName).joined(separator: " or "))
        case .notReady:
            if let text = model.evolutionStatus(of: pet.id).waitingText { second.append(text) }
        case .none:
            break
        }
        lines.append(second.joined(separator: " · "))
        return lines.joined(separator: "\n")
    }

    private func loadPortrait(_ path: String) {
        guard !requestedPortraits.contains(path) else { return }
        requestedPortraits.insert(path)
        Task {
            guard let url = await model.portrait(forPet: path), let image = NSImage(contentsOf: url) else { return }
            portraits[path] = image
            if isEditing {
                needsReload = true  // reloading the row would throw away what's being typed
                return
            }
            for (index, pet) in pets.enumerated() where pet.spritePath == path {
                table.reloadData(forRowIndexes: [index], columnIndexes: [0])
            }
        }
    }

    // MARK: - Actions

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, pets.indices.contains(field.tag) else { return }
        let pet = pets[field.tag]
        if field.stringValue != pet.name { model.rename(pet.id, to: field.stringValue) }
        window?.makeFirstResponder(nil)
        reload()  // also catches up on anything skipped while typing
    }

    @objc private func toggleBall(_ sender: NSButton) {
        guard pets.indices.contains(sender.tag) else { return }
        let pet = pets[sender.tag]
        model.setInBall(pet.id, !pet.inBall)
        reload()
    }

    @objc private func release(_ sender: NSButton) {
        guard pets.indices.contains(sender.tag) else { return }
        model.confirmRelease(pets[sender.tag].id)
        reload()
    }
}

/// Lets a click go straight into a row's text field (a plain table would select the row first).
final class ClickToEditTableView: NSTableView {
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        responder is NSTextField || super.validateProposedFirstResponder(responder, for: event)
    }
}

/// A pet row: portrait; editable name; species; stats; Release.
private final class PetCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("PetCell")

    let portrait = NSImageView()
    let name = NSTextField(string: "")
    let species = NSTextField(labelWithString: "")
    let stats = NSTextField(wrappingLabelWithString: "")
    let release = NSButton(title: "Release", target: nil, action: nil)
    let ball = NSButton(title: "Return to Ball", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        portrait.imageScaling = .scaleProportionallyUpOrDown
        name.font = .boldSystemFont(ofSize: 13)
        name.isBordered = false
        name.drawsBackground = false
        name.focusRingType = .exterior
        name.toolTip = "Click to rename"
        species.font = .systemFont(ofSize: 11)
        species.textColor = .secondaryLabelColor
        stats.font = .systemFont(ofSize: 11)
        stats.textColor = .secondaryLabelColor
        stats.maximumNumberOfLines = 2
        release.bezelStyle = .rounded
        release.controlSize = .small
        ball.bezelStyle = .rounded
        ball.controlSize = .small
        for view in [portrait, name, species, stats, release, ball] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        stats.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            portrait.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            portrait.centerYAnchor.constraint(equalTo: centerYAnchor),
            portrait.widthAnchor.constraint(equalToConstant: 56),
            portrait.heightAnchor.constraint(equalToConstant: 56),
            name.leadingAnchor.constraint(equalTo: portrait.trailingAnchor, constant: 10),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            name.trailingAnchor.constraint(equalTo: ball.leadingAnchor, constant: -8),
            ball.trailingAnchor.constraint(equalTo: release.leadingAnchor, constant: -6),
            ball.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            release.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            release.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            species.leadingAnchor.constraint(equalTo: name.leadingAnchor, constant: 2),
            species.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
            species.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stats.leadingAnchor.constraint(equalTo: species.leadingAnchor),
            stats.topAnchor.constraint(equalTo: species.bottomAnchor, constant: 2),
            stats.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
