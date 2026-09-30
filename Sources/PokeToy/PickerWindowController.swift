import AppKit
import PokeToyCore

/// Searchable list of SpriteCollab Pokémon; choosing one adds it as a new pet.
@MainActor
final class PickerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let model: AppModel
    private var all: [CatalogEntry] = []
    private var shown: [CatalogEntry] = []
    private var busy = false

    private let search = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private let addButton = NSButton(title: "Add", target: nil, action: nil)

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Add Pokémon"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 300, height: 300)
        super.init(window: window)
        buildLayout(in: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(search)
        if all.isEmpty { load(forceRefresh: false) }
    }

    private func buildLayout(in window: NSWindow) {
        search.placeholderString = "Search by name or number"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(addSelected)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        retryButton.target = self
        retryButton.action = #selector(retry)
        retryButton.isHidden = true
        addButton.target = self
        addButton.action = #selector(addSelected)
        addButton.keyEquivalent = "\r"

        let footer = NSStackView(views: [status, spinner, retryButton, addButton])
        footer.orientation = .horizontal
        let stack = NSStackView(views: [search, scroll, footer])
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
            search.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ])
    }

    private func load(forceRefresh: Bool) {
        setBusy(true, message: "Loading Pokémon list…")
        retryButton.isHidden = true
        Task {
            do {
                all = try await model.catalog(forceRefresh: forceRefresh)
                applyFilter()
                setBusy(false, message: "\(all.count) Pokémon — double-click to add")
            } catch {
                setBusy(false, message: "Couldn't reach SpriteCollab.")
                retryButton.isHidden = false
            }
        }
    }

    private func applyFilter() {
        shown = Catalog.filter(all, query: search.stringValue)
        table.reloadData()
    }

    private func setBusy(_ busy: Bool, message: String) {
        self.busy = busy
        status.stringValue = message
        addButton.isEnabled = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    @objc private func retry() {
        load(forceRefresh: true)
    }

    @objc private func addSelected() {
        guard !busy, table.selectedRow >= 0, table.selectedRow < shown.count else { return }
        let entry = shown[table.selectedRow]
        setBusy(true, message: "Downloading \(entry.displayName)…")
        Task {
            do {
                try await model.addPet(entry)
                setBusy(false, message: "Added \(entry.displayName)!")
            } catch {
                setBusy(false, message: "Couldn't load \(entry.displayName): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        shown.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let label = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? {
            let label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.lineBreakMode = .byTruncatingTail
            return label
        }()
        let entry = shown[row]
        label.stringValue = "\(entry.displayName)   #\(entry.path)"
        return label
    }
}
