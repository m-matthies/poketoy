import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct PomodoroTests {
    let pet = UUID()
    let start = Date(timeIntervalSince1970: 1_000_000)

    func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    @Test func phasesLastTheClassicTimes() {
        #expect(Pomodoro.Phase.focus.duration == 25 * 60)
        #expect(Pomodoro.Phase.shortBreak.duration == 5 * 60)
        #expect(Pomodoro.Phase.longBreak.duration == 15 * 60)
    }

    @Test func countsDown() {
        let timer = Pomodoro(petID: pet, phase: .focus, now: start)
        #expect(timer.remaining(at: at(10)) == 15 * 60)
        #expect(timer.remaining(at: at(30)) == 0)
        #expect(Pomodoro.clock(125) == "2:05")
        #expect(Pomodoro.clock(25 * 60) == "25:00")
    }

    @Test func pausingStopsTheClock() {
        var timer = Pomodoro(petID: pet, phase: .focus, now: start)
        timer.pause(at: at(10))
        #expect(timer.isPaused)
        #expect(timer.remaining(at: at(40)) == 15 * 60)
        var copy = timer
        #expect(copy.advance(at: at(40)) == nil)  // paused timers don't finish
        timer.resume(at: at(40))
        #expect(timer.remaining(at: at(50)) == 5 * 60)
    }

    @Test func aFinishedFocusStartsABreak() {
        var timer = Pomodoro(petID: pet, phase: .focus, now: start)
        #expect(timer.advance(at: at(24)) == nil)
        #expect(timer.advance(at: at(25)) == .focusDone(next: .shortBreak))
        #expect(timer.phase == .shortBreak)
        #expect(timer.remaining(at: at(26)) == 4 * 60)
        #expect(timer.focusesDone == 1)
    }

    @Test func everyFourthFocusEarnsALongBreak() {
        var timer = Pomodoro(petID: pet, phase: .focus, now: start)
        var outcomes: [Pomodoro.Outcome] = []
        var now = start
        for _ in 0..<4 {
            now = now.addingTimeInterval(25 * 60)
            if let outcome = timer.advance(at: now) { outcomes.append(outcome) }
            now = now.addingTimeInterval(timer.remaining(at: now))
            if let outcome = timer.advance(at: now) { outcomes.append(outcome) }
            timer.start(.focus, at: now)
        }
        #expect(outcomes.filter { $0 == .focusDone(next: .shortBreak) }.count == 3)
        #expect(outcomes[6] == .focusDone(next: .longBreak))
        #expect(outcomes.filter { $0 == .breakDone }.count == 4)
        #expect(timer.focusesDone == 0)  // a new round after the long break
    }

    @Test func aFinishedBreakWaitsForTheNextFocus() {
        var timer = Pomodoro(petID: pet, phase: .shortBreak, now: start)
        #expect(timer.advance(at: at(5)) == .breakDone)
        #expect(timer.isWaiting)
        #expect(timer.advance(at: at(60)) == nil)
        timer.start(.focus, at: at(60))
        #expect(timer.remaining(at: at(61)) == 24 * 60)
    }

    @Test func aSleepingMacStartsTheBreakOnWaking() {
        var timer = Pomodoro(petID: pet, phase: .focus, now: start)
        #expect(timer.advance(at: at(90)) == .focusDone(next: .shortBreak))  // woke long after
        #expect(timer.remaining(at: at(90)) == 5 * 60)
    }

    @Test func skippingEndsThePhaseNow() {
        var timer = Pomodoro(petID: pet, phase: .focus, now: start)
        #expect(timer.skip(at: at(3)) == .focusDone(next: .shortBreak))
        #expect(timer.skip(at: at(4)) == .breakDone)
    }

    @Test func survivesARelaunch() throws {
        var settings = Settings.default
        var timer = Pomodoro(petID: pet, phase: .focus, now: start)
        timer.pause(at: at(5))
        settings.pomodoro = timer
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(again.pomodoro == timer)
        let broken = #"{"pomodoro": {"phase": "nap"}}"#
        #expect(try JSONDecoder().decode(Settings.self, from: Data(broken.utf8)).pomodoro == nil)
    }

    @Test func petsCelebrateAndNudge() {
        var (playground, ids) = makePlayground([500])
        playground.celebrate(ids[0])
        let events = play(&playground, seconds: 0.1)
        #expect(events.contains(.emotion(petID: ids[0], .joyous)))
        #expect(playground.pet(ids[0])?.brain.pose.anim == .cheer)
        play(&playground, seconds: 3)
        playground.nudge(ids[0])
        let later = play(&playground, seconds: 0.1)
        #expect(later.contains(.emotion(petID: ids[0], .surprised)))
    }
}
