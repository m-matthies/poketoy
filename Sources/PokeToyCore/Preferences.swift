import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// How long a pet left alone waits before napping.
public enum NapTiming: String, Codable, CaseIterable, Sendable {
    case often, normal, rarely, never

    /// Seconds left alone before a nap (a third of it at night); nil: pets don't nap on their own.
    public var seconds: Double? {
        switch self {
        case .often: return 30
        case .normal: return PetBrain.sleepAfter
        case .rarely: return 180
        case .never: return nil
        }
    }
}

/// Which screens pets may use.
public enum ScreenChoice: String, Codable, CaseIterable, Sendable {
    case all, main
}

/// An app that hides the pets while it's in front.
public struct ExcludedApp: Codable, Equatable, Hashable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// A global keyboard shortcut: a virtual key code and Carbon modifier flags (`cmdKey`, `optionKey`, …).
public struct Shortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Needs ⌃ or ⌥ — plain typing and ⌘ combinations (⌘W, ⌘Q, ⌘C…) belong to apps — and a real key,
    /// not a modifier on its own.
    public var isValid: Bool {
        modifiers & UInt32(controlKey | optionKey) != 0 && !Self.modifierKeys.contains(Int(keyCode))
    }

    /// As menus show it: "⌃⌥⇧⌘B".
    public var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + (Self.keyNames[Int(keyCode)] ?? "Key \(keyCode)")
    }

    /// The menu item key equivalent ("b"), when the key has one.
    public var keyEquivalent: String? {
        guard let name = Self.keyNames[Int(keyCode)], name.count == 1 else { return nil }
        return name.lowercased()
    }

    private static let modifierKeys: Set<Int> = [kVK_Shift, kVK_RightShift, kVK_Control, kVK_RightControl, kVK_Option,
                                                  kVK_RightOption, kVK_Command, kVK_RightCommand, kVK_Function, kVK_CapsLock]

    private static let keyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
            kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, key) in functionKeys.enumerated() { names[key] = "F\(index + 1)" }
        return names
    }()
}

/// What the Preferences window sets.
public struct Preferences: Codable, Equatable, Sendable {
    public static let speedRange: ClosedRange<Double> = 0.5...2
    public static let defaultHiddenApps = [
        ExcludedApp(bundleID: "us.zoom.xos", name: "Zoom"),
        ExcludedApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams"),
        ExcludedApp(bundleID: "com.microsoft.teams", name: "Microsoft Teams (classic)"),
        ExcludedApp(bundleID: "Cisco-Systems.Spark", name: "Webex"),
        ExcludedApp(bundleID: "com.apple.FaceTime", name: "FaceTime"),
        ExcludedApp(bundleID: "com.apple.iWork.Keynote", name: "Keynote"),
    ]

    /// Walking speed of your pets, × normal (jumps are unaffected).
    public var petSpeed: Double = 1
    public var naps: NapTiming = .normal
    public var screens: ScreenChoice = .all
    public var feedShortcut: Shortcut? = Shortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | optionKey))
    public var catchGameShortcut: Shortcut? = Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey))
    public var showHideShortcut: Shortcut? = Shortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | optionKey))
    public var hideInFullScreen = true
    public var hiddenWhileFrontmost: [ExcludedApp] = Preferences.defaultHiddenApps
    /// 30 fps on battery; paused while the screen is locked.
    public var batterySaver = true
    /// Pets stay out of screen sharing and screenshots (their windows can't be captured, and they hide while a
    /// listed app is sharing the screen).
    public var hideFromScreenSharing = true
    public var pomodoro = PomodoroOptions()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case petSpeed, naps, screens, feedShortcut, catchGameShortcut, showHideShortcut, hideInFullScreen,
             hiddenWhileFrontmost, batterySaver, pomodoro, hideFromScreenSharing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        let speed = (try? c.decodeIfPresent(Double.self, forKey: .petSpeed)) ?? defaults.petSpeed
        petSpeed = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        naps = (try? c.decodeIfPresent(NapTiming.self, forKey: .naps)) ?? defaults.naps
        screens = (try? c.decodeIfPresent(ScreenChoice.self, forKey: .screens)) ?? defaults.screens
        // A cleared shortcut is stored as null; a missing key means "the default".
        feedShortcut = Self.shortcut(c, .feedShortcut, default: defaults.feedShortcut)
        catchGameShortcut = Self.shortcut(c, .catchGameShortcut, default: defaults.catchGameShortcut)
        showHideShortcut = Self.shortcut(c, .showHideShortcut, default: defaults.showHideShortcut)
        hideInFullScreen = (try? c.decodeIfPresent(Bool.self, forKey: .hideInFullScreen)) ?? defaults.hideInFullScreen
        hiddenWhileFrontmost = (try? c.decodeIfPresent([ExcludedApp].self, forKey: .hiddenWhileFrontmost))
            ?? defaults.hiddenWhileFrontmost
        batterySaver = (try? c.decodeIfPresent(Bool.self, forKey: .batterySaver)) ?? defaults.batterySaver
        pomodoro = (try? c.decodeIfPresent(PomodoroOptions.self, forKey: .pomodoro)) ?? defaults.pomodoro
        hideFromScreenSharing = (try? c.decodeIfPresent(Bool.self, forKey: .hideFromScreenSharing))
            ?? defaults.hideFromScreenSharing
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(petSpeed, forKey: .petSpeed)
        try c.encode(naps, forKey: .naps)
        try c.encode(screens, forKey: .screens)
        try c.encode(feedShortcut, forKey: .feedShortcut)  // nil encodes as null: cleared on purpose
        try c.encode(catchGameShortcut, forKey: .catchGameShortcut)
        try c.encode(showHideShortcut, forKey: .showHideShortcut)
        try c.encode(hideInFullScreen, forKey: .hideInFullScreen)
        try c.encode(hiddenWhileFrontmost, forKey: .hiddenWhileFrontmost)
        try c.encode(batterySaver, forKey: .batterySaver)
        try c.encode(pomodoro, forKey: .pomodoro)
        try c.encode(hideFromScreenSharing, forKey: .hideFromScreenSharing)
    }

    private static func shortcut(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys,
                                 default fallback: Shortcut?) -> Shortcut? {
        guard c.contains(key) else { return fallback }
        if (try? c.decodeNil(forKey: key)) == true { return nil }
        guard let shortcut = try? c.decode(Shortcut.self, forKey: key), shortcut.isValid else { return fallback }
        return shortcut
    }
}

/// An on-screen window, as far as screen-sharing detection needs it (window-list coordinates, origin top left).
public struct SharingWindow: Equatable, Sendable {
    public var bundleID: String?
    public var layer: Int
    public var bounds: CGRect

    public init(bundleID: String?, layer: Int, bounds: CGRect) {
        self.bundleID = bundleID
        self.layer = layer
        self.bounds = bounds
    }
}

/// When pets get out of the way on their own.
public enum AutoHide {
    public static let ownBundleID = "local.poketoy.PokeToy"

    public static func shouldHide(frontmost: String?, isFullScreen: Bool, sharing: Bool = false,
                                  preferences: Preferences) -> Bool {
        if sharing && preferences.hideFromScreenSharing { return true }
        guard let frontmost, frontmost != ownBundleID else { return false }
        if preferences.hiddenWhileFrontmost.contains(where: { $0.bundleID == frontmost }) { return true }
        return isFullScreen && preferences.hideInFullScreen
    }

    /// Whether one of the listed meeting apps seems to be sharing the screen: while sharing, Zoom, Teams and Webex
    /// show a floating toolbar — a window above the normal layer that isn't a menu bar icon.
    public static func isSharingScreen(_ windows: [SharingWindow], preferences: Preferences, screens: [CGRect]) -> Bool {
        guard preferences.hideFromScreenSharing else { return false }
        let apps = Set(preferences.hiddenWhileFrontmost.map(\.bundleID))
        return windows.contains { window in
            guard let app = window.bundleID, apps.contains(app), window.layer > 0, window.layer < 1000 else { return false }
            let inMenuBar = screens.contains { abs(window.bounds.minY - $0.minY) < 1 && window.bounds.height <= 30 }
            return !inMenuBar && window.bounds.width >= 60 && window.bounds.height >= 20
        }
    }

    /// A window exactly covering one of the screens (CG window bounds and screen frames in the same coordinates,
    /// origin top left). On screens with a camera notch, full-screen windows start below it: `topInsets[i]` is
    /// screen i's safe-area top inset.
    public static func coversAScreen(_ bounds: CGRect, screens: [CGRect], topInsets: [CGFloat] = []) -> Bool {
        for (index, screen) in screens.enumerated() {
            let inset: CGFloat = index < topInsets.count ? topInsets[index] : 0
            var belowNotch = screen
            belowNotch.origin.y += inset
            belowNotch.size.height -= inset
            if matches(bounds, screen) || matches(bounds, belowNotch) { return true }
        }
        return false
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        let edges: [CGFloat] = [a.minX - b.minX, a.minY - b.minY, a.width - b.width, a.height - b.height]
        return edges.allSatisfy { abs($0) <= 1 }
    }
}

/// Auto-hide over time: the rules, plus the player's "show them anyway" for the app in front.
public struct AutoHideState: Sendable {
    /// The app in front when the player asked to see the pets despite auto-hide.
    private var shownAnywayFor: String?

    public init() {}

    /// Whether pets should be auto-hidden now.
    public mutating func update(frontmost: String?, isFullScreen: Bool, sharing: Bool = false, preferences: Preferences,
                                gameRunning: Bool) -> Bool {
        if let shown = shownAnywayFor, shown != frontmost { shownAnywayFor = nil }  // a new app in front: rules again
        guard !gameRunning, shownAnywayFor == nil else { return false }
        return AutoHide.shouldHide(frontmost: frontmost, isFullScreen: isFullScreen, sharing: sharing,
                                   preferences: preferences)
    }

    /// The player showed the pets while `frontmost` was hiding them: leave them visible until another app is in front.
    public mutating func userShowed(frontmost: String?) {
        shownAnywayFor = frontmost
    }
}

/// How often the app ticks.
public enum FramePacing {
    public static func interval(onBattery: Bool, batterySaver: Bool) -> Double {
        onBattery && batterySaver ? 1.0 / 30 : 1.0 / 60
    }
}
