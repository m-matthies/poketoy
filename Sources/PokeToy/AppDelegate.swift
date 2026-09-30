import AppKit
import Carbon.HIToolbox
import PokeToyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var menus: MenuBuilder!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        menus = MenuBuilder(model: model)
        NSApp.mainMenu = menus.makeMainMenu()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PokeToy")
        item.menu = menus.makeStatusMenu()
        statusItem = item

        // The menus show the configurable global shortcuts, so they're rebuilt when those change.
        model.onMenusChanged = { [unowned self] in NSApp.mainMenu = self.menus.makeMainMenu() }
        model.start()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        menus.makeDockMenu()
    }

    /// Opening the app again (e.g. from Finder) shows hidden pets, else the starter choice (if still open) or the Pokédex.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.settings.hidden {
            model.setHidden(false)
        } else if model.needsStarter {
            model.showStarterChoice()
        } else {
            model.showPokedex()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.save()
    }
}
