import AppKit
import PokeToyCore

/// Every species caught in the catch game: completion, then portrait, name, first catch and count.
@MainActor
final class PokedexWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let model: AppModel
    private var rows: [(key: String, entry: PokedexEntry)] = []
    private var portraits: [String: NSImage] = [:]
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
        rows = model.settings.pokedex.map { (key: $0.key, entry: $0.value) }
            .sorted { $0.entry.firstCaught > $1.entry.firstCaught }
        header.stringValue = rows.isEmpty ? "No Pokémon caught yet — play the catch game!" : "\(rows.count) species caught"
        table.reloadData()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        Task {
            let catalog = await model.catalogForPokedex()
            guard !catalog.isEmpty else { return }
            let share = Pokedex.completion(caught: model.settings.pokedex, catalog: catalog)
            header.stringValue = "\(rows.count) species caught — \(String(format: "%.1f", share * 100))% complete"
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
        let times = entry.count == 1 ? "once" : "\(entry.count) times"
        let detail = NSTextField(labelWithString: "#\(key) · first caught \(dateFormatter.string(from: entry.firstCaught)) · \(times)")
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
