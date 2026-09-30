import AppKit
import PokeToyCore

/// Keeps a current `World` built from the screens and the on-screen window list.
@MainActor
final class WorldMonitor {
    private(set) var world = World(screens: [], surfaces: [])
    /// Pets stay on the main screen (the one with the menu bar).
    var mainScreenOnly = false
    /// The frontmost app, and whether one of its windows covers a whole screen (full screen).
    private(set) var frontmostBundleID: String?
    private(set) var frontmostIsFullScreen = false
    /// Other apps' windows above the normal layer (floating toolbars and the like), for screen-sharing detection.
    private(set) var floatingWindows: [SharingWindow] = []
    /// The screens in window-list coordinates (origin top left of the main screen), and their menu bar heights.
    private(set) var screenRectsTopLeft: [CGRect] = []
    private(set) var menuBarHeights: [CGFloat] = []
    /// Only while screen-sharing detection is on.
    var collectsFloatingWindows = true
    /// Bundle ids by process, kept between refreshes (looking them up five times a second adds up).
    private var bundleIDs: [Int32: String] = [:]
    private var bundleIDsClearedAt = Date()
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

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        let allScreens = NSScreen.screens
        let screens = (mainScreenOnly ? Array(allScreens.prefix(1)) : allScreens)
            .map { ScreenInfo(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let primaryHeight = allScreens.first?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        let frontPID = front?.processIdentifier
        frontmostBundleID = front?.bundleIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        // Screens in window-list coordinates (origin top left of the main screen).
        let cgScreens = allScreens.map {
            CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
        screenRectsTopLeft = cgScreens
        menuBarHeights = allScreens.map { max(0, $0.frame.maxY - $0.visibleFrame.maxY) }
        if Date().timeIntervalSince(bundleIDsClearedAt) > 60 {  // processes come and go
            bundleIDs = [:]
            bundleIDsClearedAt = Date()
        }
        floatingWindows = !collectsFloatingWindows ? [] : list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer > 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
            if bundleIDs[pid] == nil { bundleIDs[pid] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "" }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            return SharingWindow(bundleID: bundleIDs[pid], layer: layer, bounds: bounds, alpha: alpha)
        }
        frontmostIsFullScreen = frontPID != ownPID && list.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == frontPID, (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return false }
            return AutoHide.coversAScreen(bounds, screens: cgScreens, topInsets: allScreens.map(\.safeAreaInsets.top))
        }
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
