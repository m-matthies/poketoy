import AppKit
import Carbon.HIToolbox
import PokeToyCore

/// Menu item that runs a closure; `enabled` (if given) decides whether it can be chosen.
@MainActor
final class ActionItem: NSMenuItem, NSMenuItemValidation {
    private let handler: () -> Void
    private let isAllowed: (() -> Bool)?
    private let dynamicTitle: (() -> String)?

    init(_ title: String, key: String = "", state: NSControl.StateValue = .off, enabled: (() -> Bool)? = nil,
         dynamicTitle: (() -> String)? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        isAllowed = enabled
        self.dynamicTitle = dynamicTitle
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        self.state = state
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let dynamicTitle { menuItem.title = dynamicTitle() }
        return isAllowed?() ?? true
    }
}

extension Shortcut {
    /// The modifier flags for a menu item's key equivalent.
    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    /// The key equivalent menus use for this key — also for Space, arrows, F-keys and the like.
    var menuKey: String? {
        if let key = keyEquivalent { return key }
        let special: [Int: Int] = [
            kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
            kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
            kVK_Home: NSHomeFunctionKey, kVK_End: NSEndFunctionKey, kVK_PageUp: NSPageUpFunctionKey,
            kVK_PageDown: NSPageDownFunctionKey, kVK_ForwardDelete: NSDeleteFunctionKey,
            kVK_Space: 0x20, kVK_Return: 0x0D, kVK_Tab: 0x09, kVK_Delete: 0x08, kVK_Escape: 0x1B,
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        let code = Int(keyCode)
        let scalar = special[code] ?? functionKeys.firstIndex(of: code).map { NSF1FunctionKey + $0 }
        return scalar.flatMap(UnicodeScalar.init).map { String(Character($0)) }
    }
}

extension NSMenuItem {
    /// Shows a global shortcut next to the item (it works from any app).
    func show(_ shortcut: Shortcut?) {
        guard let shortcut, let key = shortcut.menuKey else {
            keyEquivalent = ""
            return
        }
        keyEquivalent = key
        keyEquivalentModifierMask = shortcut.menuModifiers
    }
}

extension CursorMode {
    var title: String {
        switch self {
        case .off: return "Off"
        case .follow: return "Follow Cursor"
        case .flee: return "Run from Cursor"
        }
    }
}

/// Builds the status-item, Dock and main menus from the current `AppModel` state.
@MainActor
final class MenuBuilder: NSObject, NSMenuDelegate {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populate(menu)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refreshEvolutionOptions()
        populate(menu)
    }

    func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "PokeToy")
        appMenu.addItem(withTitle: "About PokeToy",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(ActionItem("Choose Your First Pokémon…", enabled: { [unowned model] in model.needsStarter }) {
            [unowned model] in model.showStarterChoice()
        })
        let feed = ActionItem("Feed", enabled: { [unowned model] in model.canFeed }) { [unowned model] in model.feed() }
        feed.show(model.shortcut(for: .feed))
        appMenu.addItem(feed)
        appMenu.addItem(ActionItem("Play Fetch", key: "j", enabled: { [unowned model] in model.canPlayFetch }) {
            [unowned model] in model.playFetch()
        })
        let game = ActionItem("Start Catch Game", dynamicTitle: { [unowned model] in
            model.isGameRunning ? "End Catch Game" : "Start Catch Game"
        }) { [unowned model] in
            if model.isGameRunning { model.endCatchGame() } else { model.startCatchGame() }
        }
        game.show(model.shortcut(for: .catchGame))
        appMenu.addItem(game)
        appMenu.addItem(ActionItem("Pokédex…") { [unowned model] in model.showPokedex() })
        appMenu.addItem(ActionItem("Pets…") { [unowned model] in model.showPets() })
        let showHide = ActionItem("Show/Hide Pets") { [unowned model] in model.toggleHidden() }
        showHide.show(model.shortcut(for: .showHide))
        appMenu.addItem(showHide)
        appMenu.addItem(.separator())
        appMenu.addItem(ActionItem("Preferences…", key: ",") { [unowned model] in model.showPreferences() })
        appMenu.addItem(.separator())
        appMenu.addItem(ActionItem("Reset Game…", enabled: { [unowned model] in model.canReset }) {
            [unowned model] in model.confirmReset()
        })
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PokeToy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: main)

        // Menu-bar-only apps don't show this menu, but its key equivalents still work in text fields.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(window, to: main)
        return main
    }

    /// The paw menu — with no Dock icon and no visible app menu, everything is reachable from here.
    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let showHide = ActionItem(model.petsHidden ? "Show Pets" : "Hide Pets") { [unowned model] in model.toggleHidden() }
        showHide.show(model.shortcut(for: .showHide))
        menu.addItem(showHide)
        if model.needsStarter {
            menu.addItem(ActionItem("Choose Your First Pokémon…") { [unowned model] in model.showStarterChoice() })
        }
        let feed = ActionItem("Feed", enabled: { [unowned model] in model.canFeed }) { [unowned model] in model.feed() }
        feed.show(model.shortcut(for: .feed))
        menu.addItem(feed)
        menu.addItem(ActionItem("Play Fetch", enabled: { [unowned model] in model.canPlayFetch }) {
            [unowned model] in model.playFetch()
        })
        let game = model.isGameRunning ? ActionItem("End Catch Game") { [unowned model] in model.endCatchGame() }
            : ActionItem("Start Catch Game") { [unowned model] in model.startCatchGame() }
        game.show(model.shortcut(for: .catchGame))
        menu.addItem(game)
        menu.addItem(ActionItem("Pokédex…") { [unowned model] in model.showPokedex() })
        menu.addItem(.separator())

        let pets = model.settings.pets
        if pets.isEmpty {
            menu.addItem(NSMenuItem(title: model.needsStarter ? "No pets yet" : "No pets — catch some in the Catch Game",
                                    action: nil, keyEquivalent: ""))
        } else {
            let out = model.petsOnScreen
            menu.addItem(NSMenuItem(title: "Pets — \(out) of \(pets.count) out", action: nil, keyEquivalent: ""))
            for pet in pets {
                let badge = model.pomodoroBadge(for: pet.id).map { "   \($0)" } ?? ""
                let item = NSMenuItem(title: (pet.inBall ? "◓ " : "") + pet.name + badge, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                addPomodoroItems(to: submenu, petID: pet.id)
                submenu.addItem(.separator())
                addPetItems(for: pet, to: submenu)
                if submenu.items.last?.isSeparatorItem == false { submenu.addItem(.separator()) }
                addBallItem(for: pet, to: submenu)
                submenu.addItem(ActionItem("Release…") { [unowned model] in model.confirmRelease(pet.id) })
                item.submenu = submenu
                menu.addItem(item)
            }
            if out > 0 {
                menu.addItem(ActionItem("Return All to Poké Balls") { [unowned model] in model.setAllInBall(true) })
            }
            if out < pets.count {
                menu.addItem(ActionItem("Let All Out") { [unowned model] in model.setAllInBall(false) })
            }
        }
        menu.addItem(.separator())

        let cursorMenu = NSMenu()
        for mode in CursorMode.allCases {
            cursorMenu.addItem(ActionItem(mode.title, state: model.settings.cursorMode == mode ? .on : .off) {
                [unowned model] in model.setCursorMode(mode)
            })
        }
        addSubmenu(cursorMenu, titled: "Cursor", to: menu)

        let sizeMenu = NSMenu()
        for scale in 1...3 {
            sizeMenu.addItem(ActionItem("\(scale)×", state: model.settings.scale == scale ? .on : .off) {
                [unowned model] in model.setScale(scale)
            })
        }
        addSubmenu(sizeMenu, titled: "Size", to: menu)

        menu.addItem(.separator())
        menu.addItem(ActionItem("Pets…") { [unowned model] in model.showPets() })
        menu.addItem(ActionItem("Preferences…") { [unowned model] in model.showPreferences() })
        menu.addItem(ActionItem("Reset Game…", enabled: { [unowned model] in model.canReset }) {
            [unowned model] in model.confirmReset()
        })

        menu.addItem(.separator())
        menu.addItem(ActionItem("About PokeToy") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        menu.addItem(ActionItem("Quit PokeToy") { NSApp.terminate(nil) })
    }

    /// A pet's own menu (right-click or ⌃-click it): its name, the Pomodoro timer, then best friend and evolution
    /// (releasing is left to the paw menu and the Pets window, away from a quick right-click).
    func makePetMenu(for id: UUID) -> NSMenu? {
        guard let pet = model.settings.pets.first(where: { $0.id == id }) else { return nil }
        model.refreshEvolutionOptions()
        let menu = NSMenu()
        let title = NSMenuItem(title: pet.name, action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: pet.name, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(title)
        menu.addItem(.separator())
        addPomodoroItems(to: menu, petID: id)
        let petItems = NSMenu()
        addPetItems(for: pet, to: petItems)
        if petItems.numberOfItems > 0 {
            menu.addItem(.separator())
            for item in petItems.items {
                petItems.removeItem(item)
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        addBallItem(for: pet, to: menu)
        return menu
    }

    private func addBallItem(for pet: PetRecord, to menu: NSMenu) {
        menu.addItem(ActionItem(pet.inBall ? "Let Out of Poké Ball" : "Return to Poké Ball") { [unowned model] in
            model.setInBall(pet.id, !pet.inBall)
        })
    }

    /// Best friend and evolution for one pet.
    private func addPetItems(for pet: PetRecord, to menu: NSMenu) {
        if let friend = model.bestFriendName(of: pet.id) {
            menu.addItem(NSMenuItem(title: "Best friend: \(friend)", action: nil, keyEquivalent: ""))
        }
        switch model.evolutionStatus(of: pet.id) {
        case .ready(let options):
            for option in options {
                menu.addItem(ActionItem("Evolve into \(option.displayName)") { [unowned model] in
                    model.evolve(pet.id, into: option)
                })
            }
        case .notReady:
            if let text = model.evolutionStatus(of: pet.id).waitingText {
                menu.addItem(NSMenuItem(title: text, action: nil, keyEquivalent: ""))
            }
        case .none:
            break
        }
    }

    /// A pet's timer: what it's doing, its task, and the sessions to start (the built-ins and the player's own).
    private func addPomodoroItems(to menu: NSMenu, petID id: UUID) {
        let options = model.pomodoroOptions
        if let timer = model.timer(for: id) {
            menu.addItem(NSMenuItem(title: model.pomodoroStatus(for: id) ?? "Pomodoro", action: nil, keyEquivalent: ""))
            if let task = timer.task { menu.addItem(NSMenuItem(title: "Task: \(task)", action: nil, keyEquivalent: "")) }
            if timer.isWaiting {
                let icon = timer.phase.icon
                menu.addItem(ActionItem("\(icon) Start \(timer.label) — \(options.minutes(of: timer.phase)) min") {
                    [unowned model] in model.startNext(on: id)
                })
            } else if timer.isPaused {
                menu.addItem(ActionItem("Resume") { [unowned model] in model.resumePomodoro(on: id) })
            } else {
                menu.addItem(ActionItem("Pause") { [unowned model] in model.pausePomodoro(on: id) })
            }
            if !timer.isWaiting {
                menu.addItem(ActionItem("Add 5 Minutes") { [unowned model] in model.adjustPomodoro(on: id, minutes: 5) })
                if timer.remaining(at: Date()) > 6 * 60 {
                    menu.addItem(ActionItem("Take Off 5 Minutes") { [unowned model] in
                        model.adjustPomodoro(on: id, minutes: -5)
                    })
                }
                menu.addItem(ActionItem(timer.phase == .focus ? "Skip to Break" : "End Break") {
                    [unowned model] in model.skipPomodoro(on: id)
                })
            }
            let others = NSMenu()
            addSessionItems(to: others, petID: id)
            let item = NSMenuItem(title: "Start Another Session", action: nil, keyEquivalent: "")
            item.submenu = others
            menu.addItem(item)
        } else {
            menu.addItem(NSMenuItem(title: "Pomodoro", action: nil, keyEquivalent: ""))
            addSessionItems(to: menu, petID: id)
        }
        let current = model.timer(for: id)
        let task = current?.task
        if model.isOnScreen(id) {  // edited right at the pet
            let title: String
            if let current, !current.isWaiting {
                title = task == nil ? "Name Task & Set Time Left…" : "Edit Task & Time Left…"
            } else if let current, current.phase.isBreak {
                title = task == nil ? "Name a Task…" : "Rename Task…"
            } else {
                title = "Start a Task…"
            }
            menu.addItem(ActionItem(title) { [unowned model] in model.editTask(on: id) })
        }
        if task != nil {
            menu.addItem(ActionItem("Clear Task") { [unowned model] in model.setTask("", on: id) })
        }
        if model.timer(for: id) != nil {
            menu.addItem(ActionItem("Stop Timer") { [unowned model] in model.stopPomodoro(on: id) })
        }
    }

    /// One item per session: "💼 Focus — 25 min", "☕️ Walk — 10 min"…
    private func addSessionItems(to menu: NSMenu, petID id: UUID) {
        for session in model.pomodoroOptions.sessions {
            let icon = session.kind.icon
            menu.addItem(ActionItem("\(icon) \(session.name) — \(session.minutes) min") {
                [unowned model] in model.startSession(session, on: id)
            })
        }
    }

    private func addSubmenu(_ submenu: NSMenu, titled title: String? = nil, to menu: NSMenu) {
        let item = NSMenuItem(title: title ?? submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}
