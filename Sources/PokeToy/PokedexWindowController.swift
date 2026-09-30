import AppKit
import PokeToyCore

/// Every species caught in the catch game: completion, then portrait, name, first catch and count.
@MainActor
final class PokedexWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let model: AppModel
    private var rows: [(key: String, entry: PokedexEntry)] = []
    private var portraits: [String: NSImage] = [:]
    private var currentPets: Set<String> = []
    private let header = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Pokédex"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 300, height: 300)
        super.init(window: window)

        header.font = .boldSystemFont(ofSize: 15)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("species"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 48
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
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

    /// Picks up new catches and pet changes while the window is open.
    func refreshIfVisible() {
        if window?.isVisible == true { reload() }
    }

    private func reload() {
        rows = model.settings.pokedex.map { (key: $0.key, entry: $0.value) }
            .sorted { $0.entry.firstCaught > $1.entry.firstCaught }
        currentPets = model.currentPetSpecies
        header.stringValue = rows.isEmpty ? "No Pokémon yet — adopt or catch some!" : "\(rows.count) species"
        table.reloadData()
        Task {
            let catalog = await model.catalogForPokedex()
            guard !catalog.isEmpty else { return }
            let share = Pokedex.completion(caught: model.settings.pokedex, catalog: catalog)
            header.stringValue = "\(rows.count) species — \(String(format: "%.1f", share * 100))% complete"
        }
        for row in rows where portraits[row.key] == nil {
            let key = row.key
            Task {
                guard let url = await model.normalPortrait(for: key), let image = NSImage(contentsOf: url) else { return }
                portraits[key] = image
                if let index = rows.firstIndex(where: { $0.key == key }) {
                    table.reloadData(forRowIndexes: [index], columnIndexes: [0])
                }
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let (key, entry) = rows[row]
        let image = NSImageView(image: portraits[key] ?? NSImage())
        image.imageScaling = .scaleProportionallyUpOrDown
        image.widthAnchor.constraint(equalToConstant: 40).isActive = true
        image.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let name = NSTextField(labelWithString: (entry.shinyCaught ? "✦ " : "") + entry.displayName)
        name.font = .boldSystemFont(ofSize: 13)
        var parts = ["#\(key)"]
        if currentPets.contains(key) {
            parts.append("current pet")
        } else if entry.everOwned {
            parts.append("former pet")
        }
        if entry.count > 0 { parts.append(entry.count == 1 ? "caught once" : "caught \(entry.count) times") }
        parts.append("since \(dateFormatter.string(from: entry.firstCaught))")
        let detail = NSTextField(labelWithString: parts.joined(separator: " · "))
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 11)
        let text = NSStackView(views: [name, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let rowView = NSStackView(views: [image, text])
        rowView.orientation = .horizontal
        rowView.spacing = 10
        return rowView
    }
}
