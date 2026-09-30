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

@Suite struct PomodoroPreferencesTests {
    let pet = UUID()
    let start = Date(timeIntervalSince1970: 1_000_000)

    func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    @Test func defaultsAreTheClassicPomodoro() {
        let options = PomodoroOptions()
        #expect(options.focusMinutes == 25 && options.shortBreakMinutes == 5 && options.longBreakMinutes == 15)
        #expect(options.focusesPerLongBreak == 4)
        #expect(options.autoStartBreaks && !options.autoStartFocus)
        #expect(options.notifications && options.sound)
        #expect(options.duration(of: .focus) == 25 * 60)
        #expect(Preferences().pomodoro == options)
    }

    @Test func customLengths() {
        var options = PomodoroOptions()
        options.focusMinutes = 50
        options.shortBreakMinutes = 10
        var timer = Pomodoro(petID: pet, phase: .focus, now: start, options: options)
        #expect(timer.remaining(at: start) == 50 * 60)
        #expect(timer.advance(at: at(50), options: options) == .focusDone(next: .shortBreak))
        #expect(timer.remaining(at: at(50)) == 10 * 60)
    }

    @Test func customLongBreakRhythm() {
        var options = PomodoroOptions()
        options.focusesPerLongBreak = 2
        var timer = Pomodoro(petID: pet, phase: .focus, now: start, options: options)
        #expect(timer.skip(at: start, options: options) == .focusDone(next: .shortBreak))
        _ = timer.skip(at: start, options: options)
        timer.start(.focus, at: start, options: options)
        #expect(timer.skip(at: start, options: options) == .focusDone(next: .longBreak))
    }

    @Test func breaksCanWaitToBeStarted() {
        var options = PomodoroOptions()
        options.autoStartBreaks = false
        var timer = Pomodoro(petID: pet, phase: .focus, now: start, options: options)
        #expect(timer.advance(at: at(25), options: options) == .focusDone(next: .shortBreak))
        #expect(timer.isWaiting)
        #expect(timer.phase == .shortBreak)  // what starts next
    }

    @Test func theNextFocusCanStartByItself() {
        var options = PomodoroOptions()
        options.autoStartFocus = true
        var timer = Pomodoro(petID: pet, phase: .shortBreak, now: start, options: options)
        #expect(timer.advance(at: at(5), options: options) == .breakDone)
        #expect(!timer.isWaiting)
        #expect(timer.phase == .focus)
        #expect(timer.remaining(at: at(5)) == 25 * 60)
    }

    @Test func optionsDecodeTolerantly() throws {
        let json = #"{"preferences": {"pomodoro": {"focusMinutes": 500, "shortBreakMinutes": 0, "sound": false}}}"#
        let options = try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).preferences.pomodoro
        #expect(options.focusMinutes == PomodoroOptions.focusRange.upperBound)
        #expect(options.shortBreakMinutes == PomodoroOptions.breakRange.lowerBound)
        #expect(options.longBreakMinutes == 15)
        #expect(!options.sound && options.notifications)
    }
}

@Suite struct FocusEvolutionTests {
    @Test func fiftyFocusSessionsByDefault() {
        #expect(PomodoroOptions().focusSessionsToEvolve == 50)
    }

    @Test func theNumberIsClamped() throws {
        let json = #"{"preferences": {"pomodoro": {"focusSessionsToEvolve": 0}}}"#
        let options = try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).preferences.pomodoro
        #expect(options.focusSessionsToEvolve == PomodoroOptions.evolveRange.lowerBound)
        let big = #"{"preferences": {"pomodoro": {"focusSessionsToEvolve": 100000}}}"#
        #expect(try JSONDecoder().decode(Settings.self, from: Data(big.utf8)).preferences.pomodoro.focusSessionsToEvolve
                == PomodoroOptions.evolveRange.upperBound)
    }

    @Test func petsCountTheirFocusSessions() throws {
        let old = #"{"id": "00000000-0000-0000-0000-000000000025", "spritePath": "0025", "displayName": "Pikachu"}"#
        var record = try JSONDecoder().decode(PetRecord.self, from: Data(old.utf8))
        #expect(record.focusSessions == 0)
        record.focusSessions = 7
        let again = try JSONDecoder().decode(PetRecord.self, from: JSONEncoder().encode(record))
        #expect(again.focusSessions == 7)
    }
}
