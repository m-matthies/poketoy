import AppKit
import Carbon.HIToolbox
import PokeToyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var menus: MenuBuilder!
    private var statusItem: NSStatusItem?
    private var feedHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        menus = MenuBuilder(model: model)
        NSApp.mainMenu = menus.makeMainMenu()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PokeToy")
        item.menu = menus.makeStatusMenu()
        statusItem = item

        model.start()

        // ⌃⌥B feeds from any app.
        feedHotKey = GlobalHotKey(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey) { [unowned model] in model.feed() }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        menus.makeDockMenu()
    }

    /// Clicking the Dock icon shows hidden pets, otherwise opens the picker.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.settings.hidden {
            model.setHidden(false)
        } else {
            model.showPicker()
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
