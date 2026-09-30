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
            menu.addItem(NSMenuItem(title: "Pets", action: nil, keyEquivalent: ""))
            for pet in pets {
                let item = NSMenuItem(title: pet.name, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                addPetItems(for: pet, to: submenu)
                item.submenu = submenu
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        addPomodoroItems(to: menu, petID: nil)
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

    /// A pet's own menu (right-click or ⌃-click it): its name, the Pomodoro timer, then its pet items.
    func makePetMenu(for id: UUID) -> NSMenu? {
        guard let pet = model.settings.pets.first(where: { $0.id == id }) else { return nil }
        model.refreshEvolutionOptions()
        let menu = NSMenu()
        let title = NSMenuItem(title: pet.name, action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: pet.name, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(title)
        menu.addItem(.separator())
        addPomodoroItems(to: menu, petID: id)
        menu.addItem(.separator())
        addPetItems(for: pet, to: menu)
        return menu
    }

    /// Best friend, evolution and Release for one pet.
    private func addPetItems(for pet: PetRecord, to menu: NSMenu) {
        if let friend = model.bestFriendName(of: pet.id) {
            menu.addItem(NSMenuItem(title: "Best friend: \(friend)", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        }
        switch model.evolutionStatus(of: pet.id) {
        case .ready(let options):
            for option in options {
                menu.addItem(ActionItem("Evolve into \(option.displayName)") { [unowned model] in
                    model.evolve(pet.id, into: option)
                })
            }
            menu.addItem(.separator())
        case .notReady(let treatsLeft, let needsBestFriend):
            let treats = treatsLeft == 1 ? "1 more treat" : "\(treatsLeft) more treats"
            let text = treatsLeft == 0 ? "Evolves once it has a best friend"
                : "Evolves after \(treats)" + (needsBestFriend ? " and a best friend" : "")
            menu.addItem(NSMenuItem(title: text, action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        case .none:
            break
        }
        menu.addItem(ActionItem("Release…") { [unowned model] in model.confirmRelease(pet.id) })
    }

    /// The Pomodoro timer: start one (on `petID`, or the first pet from the paw menu), or control the running one.
    private func addPomodoroItems(to menu: NSMenu, petID: UUID?) {
        guard let target = petID ?? model.settings.pets.first?.id else { return }
        guard let timer = model.pomodoro else {
            menu.addItem(NSMenuItem(title: "Pomodoro", action: nil, keyEquivalent: ""))
            for phase in Pomodoro.Phase.allCases {
                let minutes = Int(phase.duration / 60)
                menu.addItem(ActionItem("\(phase == .focus ? "🍅" : "☕️") \(phase.title) — \(minutes) min") {
                    [unowned model] in model.startPomodoro(phase, on: target)
                })
            }
            return
        }
        menu.addItem(NSMenuItem(title: model.pomodoroStatus ?? "Pomodoro", action: nil, keyEquivalent: ""))
        if timer.isWaiting {
            menu.addItem(ActionItem("🍅 Start Focus — 25 min") { [unowned model] in model.startPomodoro(.focus, on: target) })
        } else if timer.isPaused {
            menu.addItem(ActionItem("Resume") { [unowned model] in model.resumePomodoro() })
        } else {
            menu.addItem(ActionItem("Pause") { [unowned model] in model.pausePomodoro() })
        }
        if !timer.isWaiting {
            let next = timer.phase == .focus ? "Skip to Break" : "End Break"
            menu.addItem(ActionItem(next) { [unowned model] in model.skipPomodoro() })
        }
        if let petID, timer.petID != petID {
            menu.addItem(ActionItem("Show Timer on This Pet") { [unowned model] in model.movePomodoro(to: petID) })
        }
        menu.addItem(ActionItem("Stop Timer") { [unowned model] in model.stopPomodoro() })
    }

    private func addSubmenu(_ submenu: NSMenu, titled title: String? = nil, to menu: NSMenu) {
        let item = NSMenuItem(title: title ?? submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}
