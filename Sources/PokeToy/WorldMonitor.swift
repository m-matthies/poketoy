import AppKit
import PokeToyCore

/// Keeps a current `World` built from the screens and the on-screen window list.
@MainActor
final class WorldMonitor {
    private(set) var world = World(screens: [], surfaces: [])
    private var timer: Timer?

    func start() {
        refresh()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let screens = NSScreen.screens.map { ScreenInfo(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var activeWindowID: Int?
        let windows: [WindowInfo] = list.compactMap { info in
            let pid = info[kCGWindowOwnerPID as String] as? Int32
            guard (info[kCGWindowLayer as String] as? Int) == 0, pid != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 80, bounds.height >= 40,
                  let number = info[kCGWindowNumber as String] as? Int else { return nil }
            // The list is front to back, so the first window of the frontmost app is its active one.
            if activeWindowID == nil, pid == frontPID { activeWindowID = number }
            return WindowInfo(id: number, cgBounds: bounds)
        }
        var snapshot = World.build(screens: screens, windows: windows, primaryScreenHeight: primaryHeight,
                                   activeWindowID: activeWindowID)
        snapshot.timestamp = CACurrentMediaTime()
        world = snapshot
    }
}
