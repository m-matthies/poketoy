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
}

extension NSMenuItem {
    /// Shows a global shortcut next to the item (it works from any app).
    func show(_ shortcut: Shortcut?) {
        guard let shortcut, let key = shortcut.keyEquivalent else {
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
        populate(menu, includeQuit: true)
        return menu
    }

    func makeDockMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu, includeQuit: false)  // the Dock adds its own Quit
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refreshEvolutionOptions()
        populate(menu, includeQuit: true)
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
        let showHide = ActionItem("Show/Hide Pets") { [unowned model] in model.setHidden(!model.settings.hidden) }
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

        let edit = NSMenu(title: "Edit")
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

    private func populate(_ menu: NSMenu, includeQuit: Bool) {
        menu.removeAllItems()
        let hidden = model.settings.hidden
        let showHide = ActionItem(hidden ? "Show Pets" : "Hide Pets") { [unowned model] in model.setHidden(!hidden) }
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
                if let friend = model.bestFriendName(of: pet.id) {
                    submenu.addItem(NSMenuItem(title: "Best friend: \(friend)", action: nil, keyEquivalent: ""))
                    submenu.addItem(.separator())
                }
                switch model.evolutionStatus(of: pet.id) {
                case .ready(let options):
                    for option in options {
                        submenu.addItem(ActionItem("Evolve into \(option.displayName)") { [unowned model] in
                            model.evolve(pet.id, into: option)
                        })
                    }
                    submenu.addItem(.separator())
                case .notReady(let treatsLeft, let needsBestFriend):
                    let treats = treatsLeft == 1 ? "1 more treat" : "\(treatsLeft) more treats"
                    let text = treatsLeft == 0 ? "Evolves once it has a best friend"
                        : "Evolves after \(treats)" + (needsBestFriend ? " and a best friend" : "")
                    submenu.addItem(NSMenuItem(title: text, action: nil, keyEquivalent: ""))
                    submenu.addItem(.separator())
                case .none:
                    break
                }
                submenu.addItem(ActionItem("Release") { [unowned model] in model.removePet(pet.id) })
                item.submenu = submenu
                menu.addItem(item)
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

        if includeQuit {
            menu.addItem(.separator())
            menu.addItem(ActionItem("Quit PokeToy") { NSApp.terminate(nil) })
        }
    }

    private func addSubmenu(_ submenu: NSMenu, titled title: String? = nil, to menu: NSMenu) {
        let item = NSMenuItem(title: title ?? submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}
