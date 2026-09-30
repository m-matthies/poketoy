import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct AppPrefsTests {
    // MARK: - Preferences

    @Test func defaults() {
        let prefs = Preferences()
        #expect(prefs.petSpeed == 1)
        #expect(prefs.naps == .normal)
        #expect(prefs.screens == .all)
        #expect(prefs.feedShortcut?.display == "⌃⌥B")
        #expect(prefs.catchGameShortcut?.display == "⌃⌥G")
        #expect(prefs.showHideShortcut?.display == "⌃⌥H")
        #expect(prefs.hideInFullScreen)
        #expect(prefs.batterySaver)
        #expect(Set(["us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime", "com.apple.iWork.Keynote",
                     "Cisco-Systems.Spark"]).isSubset(of: Set(prefs.hiddenWhileFrontmost.map(\.bundleID))))
    }

    @Test func settingsWithoutPreferencesGetTheDefaults() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"scale": 2}"#.utf8))
        #expect(old.preferences == Preferences())
    }

    @Test func preferencesRoundTripAndTolerateBadValues() throws {
        var settings = Settings.default
        settings.preferences.petSpeed = 1.5
        settings.preferences.naps = .never
        settings.preferences.screens = .main
        settings.preferences.feedShortcut = nil
        settings.preferences.hiddenWhileFrontmost = [ExcludedApp(bundleID: "com.example.app", name: "Example")]
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(again == settings)
        let bad = #"{"preferences": {"petSpeed": 9, "naps": "always", "screens": 3, "batterySaver": false}}"#
        let prefs = try JSONDecoder().decode(Settings.self, from: Data(bad.utf8)).preferences
        #expect(prefs.petSpeed == 2)  // clamped
        #expect(prefs.naps == .normal)
        #expect(prefs.screens == .all)
        #expect(!prefs.batterySaver)
        #expect(prefs.feedShortcut == Preferences().feedShortcut)  // missing: default
    }

    @Test func napTimes() {
        #expect(NapTiming.often.seconds == 30)
        #expect(NapTiming.normal.seconds == PetBrain.sleepAfter)
        #expect(NapTiming.rarely.seconds == 180)
        #expect(NapTiming.never.seconds == nil)
    }

    // MARK: - Shortcuts

    @Test func shortcutsDisplayLikeMenus() {
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | shiftKey)).display == "⇧⌘G")
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)).display == "⌃⌥⇧⌘7")
        #expect(Shortcut(keyCode: UInt32(kVK_F5), modifiers: UInt32(optionKey)).display == "⌥F5")
        #expect(Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)).display == "⌃Space")
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | optionKey)).keyEquivalent == "b")
    }

    @Test func shortcutsNeedACommandControlOrOptionKey() {
        #expect(!Shortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: 0).isValid)
        #expect(!Shortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(shiftKey)).isValid)
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(optionKey)).isValid)
        #expect(!Shortcut(keyCode: UInt32(kVK_Shift), modifiers: UInt32(controlKey)).isValid)  // a modifier alone
    }

    // MARK: - Auto-hide

    @Test func autoHideDecisions() {
        var prefs = Preferences()
        #expect(AutoHide.shouldHide(frontmost: "us.zoom.xos", isFullScreen: false, preferences: prefs))
        #expect(!AutoHide.shouldHide(frontmost: "com.apple.Safari", isFullScreen: false, preferences: prefs))
        #expect(AutoHide.shouldHide(frontmost: "com.apple.Safari", isFullScreen: true, preferences: prefs))
        #expect(!AutoHide.shouldHide(frontmost: AutoHide.ownBundleID, isFullScreen: true, preferences: prefs))
        #expect(!AutoHide.shouldHide(frontmost: nil, isFullScreen: false, preferences: prefs))
        prefs.hideInFullScreen = false
        #expect(!AutoHide.shouldHide(frontmost: "com.apple.Safari", isFullScreen: true, preferences: prefs))
        prefs.hiddenWhileFrontmost = []
        #expect(!AutoHide.shouldHide(frontmost: "us.zoom.xos", isFullScreen: false, preferences: prefs))
    }

    @Test func fullScreenMeansAWindowCoveringAScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        #expect(AutoHide.coversAScreen(CGRect(x: 1440, y: 0, width: 1920, height: 1080), screens: screens))
        #expect(!AutoHide.coversAScreen(CGRect(x: 0, y: 25, width: 1440, height: 875), screens: screens))  // just zoomed
    }

    // MARK: - Pets

    @Test func petSpeedScalesWalkingOnly() {
        func distance(speed: CGFloat) -> CGFloat {
            var (playground, ids) = makePlayground([200])
            playground.petSpeed = speed
            let start = playground.pet(ids[0])!.body.position.x
            play(&playground, seconds: 1, cursor: CGPoint(x: 900, y: 60), mode: .follow)
            return playground.pet(ids[0])!.body.position.x - start
        }
        let normal = distance(speed: 1), fast = distance(speed: 2), slow = distance(speed: 0.5)
        #expect(normal > 50)
        #expect(abs(fast / normal - 2) < 0.15)
        #expect(abs(slow / normal - 0.5) < 0.1)
    }

    func asleep(after seconds: Double, naps: NapTiming, timeOfDay: TimeOfDay = .day) -> Bool {
        var (playground, ids) = makePlayground([500])
        playground.napAfter = naps.seconds
        playground.timeOfDay = timeOfDay
        play(&playground, seconds: seconds)
        return playground.pet(ids[0])!.brain.isSleeping
    }

    @Test func napsFollowThePreference() {
        #expect(asleep(after: 45, naps: .often))
        #expect(!asleep(after: 25, naps: .often))
        #expect(!asleep(after: 150, naps: .rarely))
        #expect(!asleep(after: 600, naps: .never))
        #expect(asleep(after: 70, naps: .rarely, timeOfDay: .night))  // a third of it at night
    }

    @Test func petNicknamesAndJoinDates() throws {
        let old = #"{"id": "00000000-0000-0000-0000-000000000025", "spritePath": "0025", "displayName": "Pikachu"}"#
        var record = try JSONDecoder().decode(PetRecord.self, from: Data(old.utf8))
        #expect(record.nickname == nil && record.joined == nil)
        #expect(record.name == "Pikachu")
        record.nickname = "Sparky"
        record.displayName = "Raichu"  // evolved
        #expect(record.name == "Sparky")
        record.nickname = "   "
        #expect(record.name == "Raichu")
        let fresh = PetRecord(spritePath: "0004", displayName: "Charmander", joined: Date(timeIntervalSince1970: 100))
        let again = try JSONDecoder().decode(PetRecord.self, from: JSONEncoder().encode(fresh))
        #expect(again.joined == Date(timeIntervalSince1970: 100))
    }

    // MARK: - Battery

    @Test func framePacing() {
        #expect(FramePacing.interval(onBattery: false, batterySaver: true) == 1.0 / 60)
        #expect(FramePacing.interval(onBattery: true, batterySaver: true) == 1.0 / 30)
        #expect(FramePacing.interval(onBattery: true, batterySaver: false) == 1.0 / 60)
    }
}
