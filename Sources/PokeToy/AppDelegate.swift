import AppKit
import PokeToyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var menus: MenuBuilder!
    private var statusItem: NSStatusItem?
    private var feedShortcut: GlobalFeedShortcut?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        menus = MenuBuilder(model: model)
        NSApp.mainMenu = menus.makeMainMenu()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PokeToy")
        item.menu = menus.makeStatusMenu()
        statusItem = item

        model.start()

        let feedShortcut = GlobalFeedShortcut { [unowned model] in model.feed() }
        feedShortcut.start()
        self.feedShortcut = feedShortcut
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
