import AppKit
import PokeToyCore

/// Every species caught, owned or downloaded, by national dex number: portrait, name, status and a short description.
@MainActor
final class PokedexWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let model: AppModel
    private var rows: [PokedexRow] = []
    private var names: [String: String] = [:]
    private var downloaded: [String] = []
    private var portraits: [String: NSImage] = [:]
    private var descriptions: [String: String] = [:]
    /// Lookups started since the last reload (portraits and descriptions load as rows scroll into view).
    private var requestedPortraits: Set<String> = []
    private var requestedDescriptions: Set<String> = []
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Pokédex"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 340, height: 300)
        super.init(window: window)

        header.font = .boldSystemFont(ofSize: 15)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("species"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 78
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

    /// Picks up new catches, downloads and pet changes while the window is open.
    func refreshIfVisible() {
        if window?.isVisible == true { reload() }
    }

    private func reload() {
        requestedPortraits = Set(portraits.keys)
        requestedDescriptions = Set(descriptions.keys)
        currentPets = model.currentPetSpecies
        rebuildRows()
        Task {
            async let paths = model.downloadedSpritePaths()
            async let catalog = model.catalogForPokedex()
            let (downloadedPaths, entries) = await (paths, catalog)
            downloaded = downloadedPaths
            names = Dictionary(entries.map { ($0.path, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            rebuildRows()
            guard !entries.isEmpty else { return }
            let share = Pokedex.completion(caught: model.settings.pokedex, catalog: entries)
            header.stringValue += " — \(String(format: "%.1f", share * 100))% complete"
        }
    }

    private func rebuildRows() {
        let pokedex = model.settings.pokedex
        rows = Pokedex.rows(pokedex: pokedex, downloaded: downloaded, names: names)
        let owned = rows.filter { $0.entry != nil }.count
        header.stringValue = rows.isEmpty ? "No Pokémon yet — choose a starter and catch some!"
            : "\(owned) caught or owned · \(rows.count - owned) seen"
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = rows[row]
        load(item.key)
        let cell = (tableView.makeView(withIdentifier: PokedexCell.identifier, owner: nil) as? PokedexCell) ?? PokedexCell()
        cell.portrait.image = portraits[item.key]
        cell.portrait.alphaValue = item.entry == nil ? 0.45 : 1  // only seen: a faded portrait
        cell.name.stringValue = "#\(item.key)  " + (item.entry?.shinyCaught == true ? "✦ " : "") + item.displayName
        cell.detail.stringValue = status(of: item)
        cell.summary.stringValue = descriptions[item.key] ?? " "
        return cell
    }

    private func status(of row: PokedexRow) -> String {
        guard let entry = row.entry else { return "seen" }
        var parts: [String] = []
        if currentPets.contains(row.key) {
            parts.append("current pet")
        } else if entry.everOwned {
            parts.append("former pet")
        }
        if entry.count > 0 { parts.append(entry.count == 1 ? "caught once" : "caught \(entry.count) times") }
        parts.append("since \(dateFormatter.string(from: entry.firstCaught))")
        return parts.joined(separator: " · ")
    }

    /// Starts loading a row's portrait and description once, when it first shows.
    private func load(_ key: String) {
        if !requestedPortraits.contains(key) {
            requestedPortraits.insert(key)
            Task {
                guard let url = await model.normalPortrait(for: key), let image = NSImage(contentsOf: url) else { return }
                portraits[key] = image
                reloadRow(key)
            }
        }
        if !requestedDescriptions.contains(key) {
            requestedDescriptions.insert(key)
            Task {
                guard let text = await model.pokemonDescription(for: key) else { return }
                descriptions[key] = text
                reloadRow(key)
            }
        }
    }

    private func reloadRow(_ key: String) {
        guard let index = rows.firstIndex(where: { $0.key == key }) else { return }
        table.reloadData(forRowIndexes: [index], columnIndexes: [0])
    }
}

/// A Pokédex row: portrait on the left; name, status and a two-line description on the right.
private final class PokedexCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("PokedexCell")

    let portrait = NSImageView()
    let name = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let summary = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        portrait.imageScaling = .scaleProportionallyUpOrDown
        name.font = .boldSystemFont(ofSize: 13)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        summary.maximumNumberOfLines = 2
        summary.lineBreakMode = .byTruncatingTail
        summary.cell?.truncatesLastVisibleLine = true
        for view in [portrait, name, detail, summary] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for label in [name, detail, summary] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        NSLayoutConstraint.activate([
            portrait.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            portrait.centerYAnchor.constraint(equalTo: centerYAnchor),
            portrait.widthAnchor.constraint(equalToConstant: 48),
            portrait.heightAnchor.constraint(equalToConstant: 48),
            name.leadingAnchor.constraint(equalTo: portrait.trailingAnchor, constant: 10),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
            summary.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            summary.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            summary.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
