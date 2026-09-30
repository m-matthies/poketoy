import AppKit
import Carbon.HIToolbox
import PokeToyCore
import UniformTypeIdentifiers

/// Pet speed, naps, screens, global shortcuts, auto-hide, launch at login and the battery saver.
@MainActor
final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate {
    private unowned let model: AppModel
    private let speed = NSSlider(value: 1, minValue: Preferences.speedRange.lowerBound,
                                 maxValue: Preferences.speedRange.upperBound, target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "")
    private let naps = NSPopUpButton()
    private let screens = NSPopUpButton()
    private var shortcutButtons: [ShortcutAction: NSButton] = [:]
    private var shortcutNotes: [ShortcutAction: NSTextField] = [:]
    private let fullScreen = NSButton(checkboxWithTitle: "Hide pets while an app is full screen", target: nil, action: nil)
    private let screenSharing = NSButton(checkboxWithTitle: "Hide pets while Zoom, Teams or Webex shares the screen",
                                         target: nil, action: nil)
    private let captureExclusion = NSButton(checkboxWithTitle: "Make pets invisible to screen capture "
                                            + "(sharing, recordings and your own screenshots)", target: nil, action: nil)
    private let appsTable = NSTableView()
    private let loginItem = NSButton(checkboxWithTitle: "Launch PokeToy at login", target: nil, action: nil)
    private let loginNote = NSTextField(labelWithString: "")
    private let battery = NSButton(checkboxWithTitle: "Battery saver: 30 fps on battery, pause while the screen is locked",
                                   target: nil, action: nil)
    // Pomodoro
    private enum PomodoroNumber: Int, CaseIterable {
        case rhythm, evolve
    }
    private let sessionsTable = ClickToEditTableView()
    private let removeSessionButton = NSButton(title: "Remove", target: nil, action: nil)
    private var pomodoroSteppers: [PomodoroNumber: NSStepper] = [:]
    private var pomodoroLabels: [PomodoroNumber: NSTextField] = [:]
    private let autoBreaks = NSButton(checkboxWithTitle: "Start breaks automatically", target: nil, action: nil)
    private let autoFocus = NSButton(checkboxWithTitle: "Start the next focus automatically", target: nil, action: nil)
    private let attention = NSButton(checkboxWithTitle: "Pets come to get your attention when a timer ends",
                                     target: nil, action: nil)
    private let notifications = NSButton(checkboxWithTitle: "Show notifications", target: nil, action: nil)
    private let sound = NSButton(checkboxWithTitle: "Play a sound", target: nil, action: nil)
    private let pauseWhileClosed = NSButton(checkboxWithTitle: "Pause timers while PokeToy is closed "
                                            + "(they pick up where they left off)", target: nil, action: nil)
    // Sections, one at a time
    private let sections = NSSegmentedControl(labels: ["General", "Shortcuts & Hiding", "Pomodoro"],
                                              trackingMode: .selectOne, target: nil, action: nil)
    private var sectionViews: [NSView] = []
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

        let generalGrid = NSGridView(views: [
            [label("Pet speed:"), stack([speed, speedLabel])],
            [label("Naps:"), naps],
            [label("Pets use:"), screens],
        ])
        generalGrid.column(at: 0).xPlacement = .trailing
        generalGrid.rowSpacing = 10
        generalGrid.columnSpacing = 8

        var rows: [[NSView]] = []
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

        let general = section([generalGrid, separator(), loginItem, loginNote, battery])
        let hiding = section([grid, separator(), fullScreen, screenSharing, captureExclusion, appsLabel, appsScroll,
                              stack([add, remove, restore])])
        screenSharing.target = self
        screenSharing.action = #selector(screenSharingChanged)
        captureExclusion.target = self
        captureExclusion.action = #selector(captureExclusionChanged)
        let pomodoro = section([
            NSTextField(labelWithString: "Sessions (work sessions count as focus, relax ones as breaks):"),
            sessionsList(), pomodoroGrid(), separator(), autoBreaks, autoFocus, attention, notifications, sound,
            pauseWhileClosed,
        ])
        for box in [autoBreaks, autoFocus, attention, notifications, sound, pauseWhileClosed] {
            box.target = self
            box.action = #selector(pomodoroChanged)
        }
        sectionViews = [general, hiding, pomodoro]
        sections.target = self
        sections.action = #selector(sectionChanged)
        sections.selectedSegment = 0

        let content = NSStackView(views: [sections] + sectionViews)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.detachesHiddenViews = true
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
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: 520),
            appsScroll.widthAnchor.constraint(equalToConstant: 480),
            sections.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        ])
        showSection(0)
        window.center()
    }

    private func section(_ views: [NSView]) -> NSStackView {
        let column = NSStackView(views: views)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        return column
    }

    /// The sessions: name, length and kind of each, and buttons to add or remove the player's own.
    private func sessionsList() -> NSView {
        for (id, title, width) in [("name", "Name", 200.0), ("minutes", "Length", 130.0), ("kind", "Kind", 110.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            sessionsTable.addTableColumn(column)
        }
        sessionsTable.rowHeight = 26
        sessionsTable.dataSource = self
        sessionsTable.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = sessionsTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 480).isActive = true
        let addWork = NSButton(title: "Add Work Session", target: self, action: #selector(addWorkSession))
        let addRelax = NSButton(title: "Add Relax Session", target: self, action: #selector(addRelaxSession))
        removeSessionButton.target = self
        removeSessionButton.action = #selector(removeSession)
        let list = NSStackView(views: [scroll, stack([addWork, addRelax, removeSessionButton])])
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        return list
    }

    private var sessions: [SessionPreset] { prefs.pomodoro.sessions }

    private func sessionCell(_ column: String, row: Int) -> NSView? {
        let session = sessions[row]
        switch column {
        case "name":
            let field = NSTextField(string: session.name)
            field.isBordered = false
            field.drawsBackground = false
            field.identifier = NSUserInterfaceItemIdentifier(session.id)  // found by id, not by (shifting) row
            field.delegate = self
            field.toolTip = session.isBuiltIn ? "Built in: part of the automatic cycle (can be renamed)" : nil
            return field
        case "minutes":
            let range = PomodoroOptions.range(for: session)
            let stepper = NSStepper()
            stepper.minValue = Double(range.lowerBound)
            stepper.maxValue = Double(range.upperBound)
            stepper.integerValue = session.minutes
            stepper.autorepeat = true
            stepper.tag = row
            stepper.target = self
            stepper.action = #selector(sessionMinutesChanged(_:))
            let value = NSTextField(labelWithString: "\(session.minutes) min")
            value.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            value.widthAnchor.constraint(equalToConstant: 60).isActive = true
            return stack([value, stepper])
        default:
            if session.isBuiltIn {
                let text = NSTextField(labelWithString: session.kind == .work ? "Work" : "Relax")
                text.textColor = .secondaryLabelColor
                return text
            }
            let popup = NSPopUpButton()
            popup.addItems(withTitles: ["Work", "Relax"])
            popup.selectItem(at: session.kind == .work ? 0 : 1)
            popup.controlSize = .small
            popup.tag = row
            popup.target = self
            popup.action = #selector(sessionKindChanged(_:))
            return popup
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButton()
    }

    private func updateRemoveButton() {
        let row = sessionsTable.selectedRow
        removeSessionButton.isEnabled = sessions.indices.contains(row) && !sessions[row].isBuiltIn
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let id = field.identifier?.rawValue,
              model.pomodoroOptions.session(id) != nil else { return }
        let name = field.stringValue
        model.updatePreferences { $0.pomodoro.rename(session: id, to: name) }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.sessionsTable.reloadData() }  // after the field has let go
        }
    }

    /// Commits a name still being typed before the table changes under it.
    private func endNameEditing() {
        window?.makeFirstResponder(nil)
    }

    @objc private func sessionMinutesChanged(_ sender: NSStepper) {
        endNameEditing()
        guard sessions.indices.contains(sender.tag) else { return }
        let id = sessions[sender.tag].id
        let minutes = sender.integerValue
        model.updatePreferences { $0.pomodoro.setMinutes(minutes, ofSession: id) }
        sessionsTable.reloadData(forRowIndexes: [sender.tag], columnIndexes: [1])
    }

    @objc private func sessionKindChanged(_ sender: NSPopUpButton) {
        endNameEditing()
        guard sessions.indices.contains(sender.tag) else { return }
        let id = sessions[sender.tag].id
        let kind: SessionPreset.Kind = sender.indexOfSelectedItem == 0 ? .work : .relax
        model.updatePreferences { $0.pomodoro.setKind(kind, ofSession: id) }
    }

    @objc private func addWorkSession() {
        addSession(name: "New Work Session", minutes: 50, kind: .work)
    }

    @objc private func addRelaxSession() {
        addSession(name: "New Relax Session", minutes: 10, kind: .relax)
    }

    /// Adds a session and starts editing its name.
    private func addSession(name: String, minutes: Int, kind: SessionPreset.Kind) {
        endNameEditing()
        model.updatePreferences { _ = $0.pomodoro.addSession(name: name, minutes: minutes, kind: kind) }
        sessionsTable.reloadData()
        let row = sessions.count - 1
        sessionsTable.selectRowIndexes([row], byExtendingSelection: false)
        sessionsTable.scrollRowToVisible(row)
        sessionsTable.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func removeSession() {
        endNameEditing()
        let row = sessionsTable.selectedRow
        guard sessions.indices.contains(row), !sessions[row].isBuiltIn else { return }
        let id = sessions[row].id
        model.updatePreferences { $0.pomodoro.removeSession(id) }
        sessionsTable.reloadData()
        updateRemoveButton()
    }

    /// The long-break rhythm and what evolving takes, each with a stepper.
    private func pomodoroGrid() -> NSGridView {
        let titles: [PomodoroNumber: String] = [.rhythm: "Long break after:", .evolve: "Evolving takes:"]
        var rows: [[NSView]] = []
        for number in PomodoroNumber.allCases {
            let range = number == .rhythm ? PomodoroOptions.rhythmRange : PomodoroOptions.evolveRange
            let stepper = NSStepper()
            stepper.minValue = Double(range.lowerBound)
            stepper.maxValue = Double(range.upperBound)
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.autorepeat = true
            stepper.tag = number.rawValue
            stepper.target = self
            stepper.action = #selector(pomodoroNumberChanged(_:))
            let value = NSTextField(labelWithString: "")
            value.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
            pomodoroSteppers[number] = stepper
            pomodoroLabels[number] = value
            rows.append([label(titles[number]!), stack([value, stepper])])
        }
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        return grid
    }

    @objc private func sectionChanged() {
        showSection(sections.selectedSegment)
    }

    /// Shows one section and fits the window to it, keeping its top edge in place.
    private func showSection(_ index: Int) {
        stopRecording()
        for (i, view) in sectionViews.enumerated() { view.isHidden = i != index }
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    private func pomodoroValue(_ number: PomodoroNumber, _ options: PomodoroOptions) -> Int {
        switch number {
        case .rhythm: return options.focusesPerLongBreak
        case .evolve: return options.focusSessionsToEvolve
        }
    }

    private func pomodoroText(_ number: PomodoroNumber, _ value: Int) -> String {
        switch number {
        case .rhythm: return value == 1 ? "1 focus" : "\(value) focuses"
        case .evolve: return (value == 1 ? "1 focus session" : "\(value) focus sessions") + " (and \(Evolution.treatsNeeded) treats and a best friend)"
        }
    }

    @objc private func pomodoroNumberChanged(_ sender: NSStepper) {
        guard let number = PomodoroNumber(rawValue: sender.tag) else { return }
        let value = Int(sender.intValue)
        model.updatePreferences { prefs in
            switch number {
            case .rhythm: prefs.pomodoro.focusesPerLongBreak = value
            case .evolve: prefs.pomodoro.focusSessionsToEvolve = value
            }
        }
        pomodoroLabels[number]?.stringValue = pomodoroText(number, value)
    }

    @objc private func pomodoroChanged() {
        let values = (autoBreaks.state == .on, autoFocus.state == .on, attention.state == .on,
                      notifications.state == .on, sound.state == .on, pauseWhileClosed.state == .off)
        model.updatePreferences { prefs in
            prefs.pomodoro.autoStartBreaks = values.0
            prefs.pomodoro.autoStartFocus = values.1
            prefs.pomodoro.seekAttention = values.2
            prefs.pomodoro.notifications = values.3
            prefs.pomodoro.sound = values.4
            prefs.pomodoro.keepRunningWhileClosed = values.5
        }
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
        screenSharing.state = prefs.hideFromScreenSharing ? .on : .off
        captureExclusion.state = prefs.excludeFromCapture ? .on : .off
        appsTable.reloadData()
        if !(window?.firstResponder is NSTextView) { sessionsTable.reloadData() }  // not while a name is typed
        updateRemoveButton()
        loginItem.state = model.launchesAtLogin || model.launchAtLoginNeedsApproval ? .on : .off
        loginNote.stringValue = model.launchAtLoginNeedsApproval
            ? "Allow PokeToy in System Settings → General → Login Items." : ""
        battery.state = prefs.batterySaver ? .on : .off
        let options = prefs.pomodoro
        for number in PomodoroNumber.allCases {
            let value = pomodoroValue(number, options)
            pomodoroSteppers[number]?.integerValue = value
            pomodoroLabels[number]?.stringValue = pomodoroText(number, value)
        }
        autoBreaks.state = options.autoStartBreaks ? .on : .off
        autoFocus.state = options.autoStartFocus ? .on : .off
        attention.state = options.seekAttention ? .on : .off
        notifications.state = options.notifications ? .on : .off
        sound.state = options.sound ? .on : .off
        pauseWhileClosed.state = options.keepRunningWhileClosed ? .off : .on
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

    @objc private func screenSharingChanged() {
        let on = screenSharing.state == .on
        model.updatePreferences { $0.hideFromScreenSharing = on }
    }

    @objc private func captureExclusionChanged() {
        let on = captureExclusion.state == .on
        model.updatePreferences { $0.excludeFromCapture = on }
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
        tableView === sessionsTable ? sessions.count : prefs.hiddenWhileFrontmost.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sessionsTable { return sessionCell(tableColumn?.identifier.rawValue ?? "name", row: row) }
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
