import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct TaskEditFixTests {
    let pet = UUID()
    let start = Date(timeIntervalSince1970: 1_000_000)

    func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    @Test func untouchedMinutesAreLeftAloneAcrossAMinuteBoundary() {
        let timer = Pomodoro(petID: pet, phase: .focus, now: start)
        let opened = TaskEditSnapshot(timer: timer, now: at(0.98))  // shows 25
        let result = TaskEdit.apply(name: "Report", minutes: 25, snapshot: opened, to: timer, petID: pet,
                                    committed: .returnKey, now: at(3), options: PomodoroOptions())
        #expect((result.timer?.remaining(at: at(3)) ?? 0) == 22 * 60)  // not reset to 25
        #expect(result.timer?.task == "Report")
    }

    @Test func changedMinutesSetTheTimeLeft() {
        let timer = Pomodoro(petID: pet, phase: .focus, now: start)
        let opened = TaskEditSnapshot(timer: timer, now: at(1))
        let result = TaskEdit.apply(name: "Report", minutes: 40, snapshot: opened, to: timer, petID: pet,
                                    committed: .returnKey, now: at(2), options: PomodoroOptions())
        #expect((result.timer?.remaining(at: at(2)) ?? 0) == 40 * 60)
    }

    @Test func aPhaseThatEndedWhileTypingOnlyGetsTheName() {
        var timer = Pomodoro(petID: pet, phase: .focus, now: start)
        let opened = TaskEditSnapshot(timer: timer, now: at(5))  // focus, 20 min left
        _ = timer.advance(at: at(25))  // the break started meanwhile
        let result = TaskEdit.apply(name: "Report", minutes: 30, snapshot: opened, to: timer, petID: pet,
                                    committed: .returnKey, now: at(26), options: PomodoroOptions())
        #expect(result.timer?.phase == .shortBreak)
        #expect((result.timer?.remaining(at: at(26)) ?? 0) == 4 * 60)
        #expect(result.timer?.task == "Report" && !result.started)
    }

    @Test func onlyReturnStartsAFocus() {
        let opened = TaskEditSnapshot(timer: nil, now: start)
        let elsewhere = TaskEdit.apply(name: "Report", minutes: 45, snapshot: opened, to: nil, petID: pet,
                                       committed: .elsewhere, now: start, options: PomodoroOptions())
        #expect(elsewhere.timer?.isWaiting == true && elsewhere.timer?.task == "Report" && !elsewhere.started)
        let blank = TaskEdit.apply(name: "  ", minutes: 45, snapshot: opened, to: nil, petID: pet,
                                   committed: .elsewhere, now: start, options: PomodoroOptions())
        #expect(blank.timer == nil)  // nothing typed, nothing made
        let returned = TaskEdit.apply(name: "Report", minutes: 45, snapshot: opened, to: nil, petID: pet,
                                      committed: .returnKey, now: start, options: PomodoroOptions())
        #expect(returned.started && (returned.timer?.remaining(at: start) ?? 0) == 45 * 60)
    }
}

@Suite struct SharingDetectionFixTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let menuBar: CGFloat = 37  // notched display

    func sharing(_ windows: [SharingWindow]) -> Bool {
        AutoHide.isSharingScreen(windows, preferences: Preferences(), screens: [screen], menuBarHeights: [menuBar])
    }

    @Test func zoomsShareToolbarAndGreenBorderCount() {
        #expect(sharing([SharingWindow(bundleID: "us.zoom.xos", layer: 3, bounds: CGRect(x: 500, y: 40, width: 420, height: 50))]))
        #expect(sharing([SharingWindow(bundleID: "us.zoom.xos", layer: 25, bounds: screen, alpha: 0.02)]))  // the border
    }

    @Test func meetingWindowsDialogsMenusAndInvisibleWindowsDont() {
        let miniMeeting = SharingWindow(bundleID: "us.zoom.xos", layer: 3, bounds: CGRect(x: 1100, y: 600, width: 320, height: 180))
        let dialog = SharingWindow(bundleID: "us.zoom.xos", layer: 8, bounds: CGRect(x: 500, y: 300, width: 400, height: 60))
        let popUp = SharingWindow(bundleID: "us.zoom.xos", layer: 101, bounds: CGRect(x: 500, y: 300, width: 200, height: 60))
        let invisible = SharingWindow(bundleID: "us.zoom.xos", layer: 3, bounds: CGRect(x: 500, y: 40, width: 420, height: 50),
                                      alpha: 0)
        let menuBarIcon = SharingWindow(bundleID: "us.zoom.xos", layer: 25, bounds: CGRect(x: 1200, y: 0, width: 36, height: 37))
        #expect(!sharing([miniMeeting, dialog, popUp, invisible, menuBarIcon]))
    }

    @Test func onlyMeetingAppsCountNotEveryAppInTheHideList() {
        var prefs = Preferences()
        prefs.hiddenWhileFrontmost.append(ExcludedApp(bundleID: "com.google.Chrome", name: "Chrome"))
        let chromePiP = SharingWindow(bundleID: "com.google.Chrome", layer: 3, bounds: CGRect(x: 500, y: 40, width: 420, height: 50))
        #expect(!AutoHide.isSharingScreen([chromePiP], preferences: prefs, screens: [screen], menuBarHeights: [menuBar]))
    }
}

@Suite struct CleanupFixTests {
    @Test func releasingAPetFromItsBallForgetsItsFriendships() {
        var (playground, ids) = makePlayground([300, 400])
        playground.friendships.add(ids[0], ids[1], 30)
        playground.stowPet(ids[0])
        playground.removePet(ids[0])  // released while in its ball
        #expect(playground.friendships.score(ids[0], ids[1]) == 0)
    }

    @Test func timersOfPetsThatAreGoneAreDropped() throws {
        let kept = PetRecord(spritePath: "0025", displayName: "Pikachu")
        var settings = Settings.default
        settings.pets = [kept]
        settings.timers = [Pomodoro(petID: kept.id, phase: .focus, now: Date()),
                           Pomodoro(petID: UUID(), phase: .focus, now: Date())]
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(again.timers.map(\.petID) == [kept.id])
    }
}
