import AppKit
import PokeToyCore

/// Menu item that runs a closure.
@MainActor
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", state: NSControl.StateValue = .off, handler: @escaping () -> Void) {
        self.handler = handler
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
        populate(menu, includeQuit: true)
    }

    func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "PokeToy")
        appMenu.addItem(withTitle: "About PokeToy",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(ActionItem("Add Pokémon…", key: "n") { [unowned model] in model.showPicker() })
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
        menu.addItem(.separator())

        let pets = model.settings.pets
        if pets.isEmpty {
            menu.addItem(NSMenuItem(title: "No pets yet", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Pets", action: nil, keyEquivalent: ""))
            for pet in pets {
                let item = NSMenuItem(title: pet.displayName, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
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
