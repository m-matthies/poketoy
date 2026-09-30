import AppKit
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
        appMenu.addItem(ActionItem("Add Pokémon…", key: "n") { [unowned model] in model.showPicker() })
        let feed = ActionItem("Feed", key: "b", enabled: { [unowned model] in model.canFeed }) { [unowned model] in model.feed() }
        feed.keyEquivalentModifierMask = [.control, .option]
        appMenu.addItem(feed)
        appMenu.addItem(ActionItem("Play Fetch", key: "j", enabled: { [unowned model] in model.canPlayFetch }) {
            [unowned model] in model.playFetch()
        })
        appMenu.addItem(ActionItem("Start Catch Game", key: "g", dynamicTitle: { [unowned model] in
            model.isGameRunning ? "End Catch Game" : "Start Catch Game"
        }) { [unowned model] in
            if model.isGameRunning { model.endCatchGame() } else { model.startCatchGame() }
        })
        appMenu.addItem(ActionItem("Daily Challenge", enabled: { [unowned model] in !model.isGameRunning }) {
            [unowned model] in model.startCatchGame(daily: true)
        })
        appMenu.addItem(ActionItem("Pokédex…") { [unowned model] in model.showPokedex() })
        appMenu.addItem(ActionItem("Show/Hide Pets") { [unowned model] in model.setHidden(!model.settings.hidden) })
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
        menu.addItem(ActionItem(hidden ? "Show Pets" : "Hide Pets") { [unowned model] in model.setHidden(!hidden) })
        menu.addItem(ActionItem("Add Pokémon…") { [unowned model] in model.showPicker() })
        menu.addItem(ActionItem("Feed", enabled: { [unowned model] in model.canFeed }) { [unowned model] in model.feed() })
        menu.addItem(ActionItem("Play Fetch", enabled: { [unowned model] in model.canPlayFetch }) {
            [unowned model] in model.playFetch()
        })
        if model.isGameRunning {
            menu.addItem(ActionItem("End Catch Game") { [unowned model] in model.endCatchGame() })
        } else {
            menu.addItem(ActionItem("Start Catch Game") { [unowned model] in model.startCatchGame() })
            menu.addItem(ActionItem("Daily Challenge") { [unowned model] in model.startCatchGame(daily: true) })
        }
        menu.addItem(ActionItem("Pokédex…") { [unowned model] in model.showPokedex() })
        menu.addItem(.separator())

        let pets = model.settings.pets
        if pets.isEmpty {
            menu.addItem(NSMenuItem(title: "No pets yet", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Pets", action: nil, keyEquivalent: ""))
            for pet in pets {
                let item = NSMenuItem(title: pet.displayName, action: nil, keyEquivalent: "")
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
                submenu.addItem(ActionItem("Remove") { [unowned model] in model.removePet(pet.id) })
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
