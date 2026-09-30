import AppKit
import Carbon.HIToolbox
import PokeToyCore
import UniformTypeIdentifiers

/// Pet speed, naps, screens, global shortcuts, auto-hide, launch at login and the battery saver.
@MainActor
final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let model: AppModel
    private let speed = NSSlider(value: 1, minValue: Preferences.speedRange.lowerBound,
                                 maxValue: Preferences.speedRange.upperBound, target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "")
    private let naps = NSPopUpButton()
    private let screens = NSPopUpButton()
    private var shortcutButtons: [ShortcutAction: NSButton] = [:]
    private var shortcutNotes: [ShortcutAction: NSTextField] = [:]
    private let fullScreen = NSButton(checkboxWithTitle: "Hide pets while an app is full screen", target: nil, action: nil)
    private let appsTable = NSTableView()
    private let loginItem = NSButton(checkboxWithTitle: "Launch PokeToy at login", target: nil, action: nil)
    private let loginNote = NSTextField(labelWithString: "")
    private let battery = NSButton(checkboxWithTitle: "Battery saver: 30 fps on battery, pause while the screen is locked",
                                   target: nil, action: nil)
    /// The shortcut being recorded, and the key monitor doing it.
    private var recording: ShortcutAction?
    private var keyMonitor: Any?

    private static let napTitles: [(NapTiming, String)] = [
        (.often, "Often (after 30 s alone)"), (.normal, "Normal (after 1 min)"), (.rarely, "Rarely (after 3 min)"),
        (.never, "Never (only while you're away)"),
    ]
    private static let screenTitles: [(ScreenChoice, String)] = [(.all, "All screens"), (.main, "Main screen only")]

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "PokeToy Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build(in: window)
        // Recording stops as soon as the window closes or loses focus, so shortcuts are never left switched off.
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopRecording() }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func refreshIfVisible() {
        if window?.isVisible == true { refresh() }
    }

    func show() {
        refresh()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func build(in window: NSWindow) {
        speed.target = self
        speed.action = #selector(speedChanged)
        speed.isContinuous = true
        naps.addItems(withTitles: Self.napTitles.map(\.1))
        naps.target = self
        naps.action = #selector(napsChanged)
        screens.addItems(withTitles: Self.screenTitles.map(\.1))
        screens.target = self
        screens.action = #selector(screensChanged)

        var rows: [[NSView]] = [
            [label("Pet speed:"), stack([speed, speedLabel])],
            [label("Naps:"), naps],
            [label("Pets use:"), screens],
        ]
        for action in ShortcutAction.allCases {
            let button = NSButton(title: "", target: self, action: #selector(recordShortcut(_:)))
            button.tag = ShortcutAction.allCases.firstIndex(of: action)!
            button.widthAnchor.constraint(equalToConstant: 130).isActive = true
            let clear = NSButton(title: "Clear", target: self, action: #selector(clearShortcut(_:)))
            clear.tag = button.tag
            let note = NSTextField(labelWithString: "")
            note.textColor = .systemRed
            note.font = .systemFont(ofSize: 11)
            shortcutButtons[action] = button
            shortcutNotes[action] = note
            rows.append([label("\(action.title):"), stack([button, clear, note])])
        }

        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 8

        fullScreen.target = self
        fullScreen.action = #selector(fullScreenChanged)
        let appsLabel = NSTextField(labelWithString: "Hide pets while these apps are in front:")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        appsTable.addTableColumn(column)
        appsTable.headerView = nil
        appsTable.dataSource = self
        appsTable.delegate = self
        let appsScroll = NSScrollView()
        appsScroll.documentView = appsTable
        appsScroll.hasVerticalScroller = true
        appsScroll.borderType = .bezelBorder
        appsScroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        let add = NSButton(title: "Add App…", target: self, action: #selector(addApp))
        let remove = NSButton(title: "Remove", target: self, action: #selector(removeApp))
        let restore = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreApps))

        loginItem.target = self
        loginItem.action = #selector(loginChanged)
        loginNote.textColor = .secondaryLabelColor
        loginNote.font = .systemFont(ofSize: 11)
        battery.target = self
        battery.action = #selector(batteryChanged)

        let content = NSStackView(views: [
            grid, separator(), fullScreen, appsLabel, appsScroll, stack([add, remove, restore]), separator(),
            loginItem, loginNote, battery,
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        content.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(content)
        window.contentView = root
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            appsScroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40),
        ])
        window.setContentSize(content.fittingSize)
        window.center()
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func stack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    // MARK: - State

    private var prefs: Preferences { model.settings.preferences }

    private func refresh() {
        speed.doubleValue = prefs.petSpeed
        speedLabel.stringValue = String(format: "%.1f×", prefs.petSpeed)
        naps.selectItem(at: Self.napTitles.firstIndex { $0.0 == prefs.naps } ?? 1)
        screens.selectItem(at: Self.screenTitles.firstIndex { $0.0 == prefs.screens } ?? 0)
        for action in ShortcutAction.allCases {
            shortcutButtons[action]?.title = recording == action ? "Type a shortcut…"
                : model.shortcut(for: action)?.display ?? "Record Shortcut"
            shortcutNotes[action]?.stringValue = recording == action ? "Use ⌃ or ⌥ · Esc cancels"
                : model.unavailableShortcuts.contains(action) ? "In use by another app" : ""
            shortcutNotes[action]?.textColor = recording == action ? .secondaryLabelColor : .systemRed
        }
        fullScreen.state = prefs.hideInFullScreen ? .on : .off
        appsTable.reloadData()
        loginItem.state = model.launchesAtLogin || model.launchAtLoginNeedsApproval ? .on : .off
        loginNote.stringValue = model.launchAtLoginNeedsApproval
            ? "Allow PokeToy in System Settings → General → Login Items." : ""
        battery.state = prefs.batterySaver ? .on : .off
    }

    // MARK: - Actions

    @objc private func speedChanged() {
        let value = (speed.doubleValue * 10).rounded() / 10
        // While dragging, only the speed changes; letting go saves.
        let released = NSApp.currentEvent?.type == .leftMouseUp
        guard value != prefs.petSpeed || released else { return }
        model.updatePreferences(save: released) { $0.petSpeed = value }
        speedLabel.stringValue = String(format: "%.1f×", value)
    }

    @objc private func napsChanged() {
        let choice = Self.napTitles[max(0, naps.indexOfSelectedItem)].0
        model.updatePreferences { $0.naps = choice }
    }

    @objc private func screensChanged() {
        let choice = Self.screenTitles[max(0, screens.indexOfSelectedItem)].0
        model.updatePreferences { $0.screens = choice }
    }

    @objc private func fullScreenChanged() {
        let on = fullScreen.state == .on
        model.updatePreferences { $0.hideInFullScreen = on }
    }

    @objc private func batteryChanged() {
        let on = battery.state == .on
        model.updatePreferences { $0.batterySaver = on }
    }

    @objc private func loginChanged() {
        do {
            try model.setLaunchAtLogin(loginItem.state == .on)
        } catch {
            NSSound.beep()
            loginItem.state = model.launchesAtLogin || model.launchAtLoginNeedsApproval ? .on : .off
            loginNote.stringValue = "Couldn't change it: \(error.localizedDescription)"
            return
        }
        refresh()
    }

    // MARK: - Shortcuts

    @objc private func recordShortcut(_ sender: NSButton) {
        let action = ShortcutAction.allCases[sender.tag]
        stopRecording()
        recording = action
        refresh()
        // Global shortcuts would fire instead of being recorded: let them go while recording.
        model.suspendShortcuts()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let used = MainActor.assumeIsolated { self?.record(event) ?? false }
            return used ? nil : event
        }
    }

    /// Handles a key press while recording: true when it was used, false to pass it on.
    private func record(_ event: NSEvent) -> Bool {
        // Only keys typed into this window are recorded; other PokeToy windows keep working.
        guard let action = recording, event.window === window else { return false }
        let held = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape) && held.isEmpty {
            stopRecording()  // Esc cancels
            return true
        }
        if held.contains(.command) && held.isDisjoint(with: [.control, .option]) {
            stopRecording()  // ⌘W, ⌘Q, … mean what they always do
            return false
        }
        let flags = event.modifierFlags
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: UInt32(modifiers))
        guard shortcut.isValid else {
            NSSound.beep()  // needs ⌃ or ⌥
            return true
        }
        recording = nil
        removeMonitor()
        // One combination does one thing: take it away from any other action first.
        for other in ShortcutAction.allCases where other != action && model.shortcut(for: other) == shortcut {
            model.setShortcut(nil, for: other)
        }
        model.setShortcut(shortcut, for: action)
        model.resumeShortcuts()
        refresh()
        return true
    }

    @objc private func clearShortcut(_ sender: NSButton) {
        stopRecording()
        model.setShortcut(nil, for: ShortcutAction.allCases[sender.tag])
        refresh()
    }

    private func stopRecording() {
        guard recording != nil || keyMonitor != nil else { return }
        recording = nil
        removeMonitor()
        model.resumeShortcuts()
        refresh()
    }

    private func removeMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - Apps

    func numberOfRows(in tableView: NSTableView) -> Int {
        prefs.hiddenWhileFrontmost.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = prefs.hiddenWhileFrontmost[row]
        let text = NSTextField(labelWithString: app.name)
        text.toolTip = app.bundleID
        let icon = NSImageView()
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            icon.image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            text.textColor = .secondaryLabelColor  // not installed
        }
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return stack([icon, text])
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { url -> ExcludedApp? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return ExcludedApp(bundleID: id, name: name)
        }
        model.updatePreferences { prefs in
            for app in added where !prefs.hiddenWhileFrontmost.contains(where: { $0.bundleID == app.bundleID }) {
                prefs.hiddenWhileFrontmost.append(app)
            }
        }
        refresh()
    }

    @objc private func removeApp() {
        let rows = appsTable.selectedRowIndexes
        guard !rows.isEmpty else { return }
        model.updatePreferences { prefs in
            prefs.hiddenWhileFrontmost = prefs.hiddenWhileFrontmost.enumerated()
                .filter { !rows.contains($0.offset) }.map(\.element)
        }
        refresh()
    }

    @objc private func restoreApps() {
        model.updatePreferences { $0.hiddenWhileFrontmost = Preferences.defaultHiddenApps }
        refresh()
    }
}
