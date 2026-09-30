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
        settings.timers = [timer]
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(again.timers == [timer])
        let broken = #"{"timers": [{"phase": "nap"}]}"#
        #expect(try JSONDecoder().decode(Settings.self, from: Data(broken.utf8)).timers.isEmpty)
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

@Suite struct SessionPresetTests {
    let pet = UUID()
    let start = Date(timeIntervalSince1970: 1_000_000)

    func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    @Test func threeBuiltInSessions() {
        let sessions = PomodoroOptions().sessions
        #expect(sessions.map(\.id) == ["focus", "shortBreak", "longBreak"])
        #expect(sessions.map(\.name) == ["Focus", "Short Break", "Long Break"])
        #expect(sessions.map(\.minutes) == [25, 5, 15])
        #expect(sessions.map(\.kind) == [.work, .relax, .relax])
        #expect(sessions.allSatisfy { $0.isBuiltIn })
    }

    @Test func builtInLengthsAreTheCycleLengths() {
        var options = PomodoroOptions()
        options.focusMinutes = 40
        #expect(options.sessions[0].minutes == 40)
        options.sessions[1].minutes = 7
        #expect(options.shortBreakMinutes == 7)
        #expect(options.duration(of: .shortBreak) == 7 * 60)
    }

    @Test func addingRenamingAndRemovingSessions() {
        var options = PomodoroOptions()
        let deep = options.addSession(name: "Deep Work", minutes: 50, kind: .work)
        let walk = options.addSession(name: "Walk", minutes: 10, kind: .relax)
        #expect(options.sessions.map(\.name) == ["Focus", "Short Break", "Long Break", "Deep Work", "Walk"])
        options.rename(session: "focus", to: "Work")
        options.rename(session: walk, to: "   ")  // blank: keeps its name
        #expect(options.sessions.map(\.name) == ["Work", "Short Break", "Long Break", "Deep Work", "Walk"])
        options.removeSession(deep)
        options.removeSession("focus")  // built-ins stay
        #expect(options.sessions.map(\.name) == ["Work", "Short Break", "Long Break", "Walk"])
    }

    @Test func aCustomWorkSessionCountsAsAFocus() {
        var options = PomodoroOptions()
        let deepID = options.addSession(name: "Deep Work", minutes: 50, kind: .work)
        let deep = options.session(deepID)!
        var timer = Pomodoro(petID: pet, session: deep, now: start, options: options)
        #expect(timer.label == "Deep Work")
        #expect(timer.phase == .focus)
        #expect(timer.remaining(at: start) == 50 * 60)
        #expect(timer.advance(at: at(50), options: options) == .focusDone(next: .shortBreak))
        #expect(timer.focusesDone == 1)
        #expect(timer.label == "Short Break")
    }

    @Test func aCustomRelaxSessionIsABreak() {
        var options = PomodoroOptions()
        let walkID = options.addSession(name: "Walk", minutes: 10, kind: .relax)
        let walk = options.session(walkID)!
        var timer = Pomodoro(petID: pet, session: walk, now: start, options: options)
        #expect(timer.phase.isBreak)
        #expect(timer.advance(at: at(10), options: options) == .breakDone)
        #expect(timer.isWaiting)
        #expect(timer.label == "Focus")  // what starts next
    }

    @Test func renamedBuiltInsNameTheCycle() {
        var options = PomodoroOptions()
        options.rename(session: "focus", to: "Work")
        options.rename(session: "shortBreak", to: "Relax")
        var timer = Pomodoro(petID: pet, phase: .focus, now: start, options: options)
        #expect(timer.label == "Work")
        _ = timer.advance(at: at(25), options: options)
        #expect(timer.label == "Relax")
    }

    @Test func sessionsDecodeTolerantly() throws {
        // Older preferences had only the lengths.
        let old = #"{"preferences": {"pomodoro": {"focusMinutes": 30, "shortBreakMinutes": 6}}}"#
        let options = try JSONDecoder().decode(Settings.self, from: Data(old.utf8)).preferences.pomodoro
        #expect(options.sessions.map(\.minutes) == [30, 6, 15])
        // Built-ins missing from a list come back; bad entries are fixed or dropped.
        let messy = #"""
        {"preferences": {"pomodoro": {"sessions": [
          {"id": "x1", "name": "Read", "minutes": 999, "kind": "work"},
          {"id": "x1", "name": "Duplicate", "minutes": 5, "kind": "relax"},
          {"id": "x2", "name": "", "minutes": 10, "kind": "nap"},
          {"id": "shortBreak", "name": "Relax", "minutes": 8, "kind": "work"}
        ]}}}
        """#
        let fixed = try JSONDecoder().decode(Settings.self, from: Data(messy.utf8)).preferences.pomodoro
        #expect(fixed.sessions.map(\.id) == ["focus", "shortBreak", "longBreak", "x1"])
        #expect(fixed.sessions[1].name == "Relax" && fixed.sessions[1].minutes == 8 && fixed.sessions[1].kind == .relax)
        #expect(fixed.sessions[3].minutes == PomodoroOptions.sessionRange.upperBound)
    }

    @Test func timersSavedBeforeLabelsStillLoad() throws {
        let timer = Pomodoro(petID: pet, phase: .longBreak, now: start)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(timer)) as! [String: Any]
        json["label"] = nil
        let again = try JSONDecoder().decode(Pomodoro.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(again.label == "Long Break")
    }
}

@Suite struct PetTimerTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func everyPetCanCarryItsOwnTimer() throws {
        let (a, b) = (UUID(), UUID())
        var settings = Settings.default
        settings.timers = [Pomodoro(petID: a, phase: .focus, now: start), Pomodoro(petID: b, phase: .shortBreak, now: start),
                           Pomodoro(petID: a, phase: .longBreak, now: start)]  // a second one for a: dropped
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(again.timers.map(\.petID) == [a, b])
        #expect(again.timers.map(\.phase) == [.focus, .shortBreak])
    }

    @Test func aSavedSingleTimerIsKept() throws {
        let timer = Pomodoro(petID: UUID(), phase: .focus, now: start)
        let json = "{\"pomodoro\": \(String(data: try JSONEncoder().encode(timer), encoding: .utf8)!)}"
        #expect(try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).timers == [timer])
    }

    @Test func timersCanNameATask() throws {
        var timer = Pomodoro(petID: UUID(), phase: .focus, now: start)
        #expect(timer.task == nil)
        timer.setTask("  Write the report  ")
        #expect(timer.task == "Write the report")
        let again = try JSONDecoder().decode(Pomodoro.self, from: JSONEncoder().encode(timer))
        #expect(again.task == "Write the report")
        timer.setTask("   ")
        #expect(timer.task == nil)
    }

    @Test func aTimerCanWaitToBeStarted() {
        var options = PomodoroOptions()
        options.rename(session: "focus", to: "Work")
        var timer = Pomodoro.waiting(petID: UUID(), options: options)
        #expect(timer.isWaiting && timer.phase == .focus && timer.label == "Work")
        timer.setTask("Emails")
        timer.start(.focus, at: start, options: options)
        #expect(timer.remaining(at: start) == 25 * 60)
        #expect(timer.task == "Emails")  // the task stays for the session
    }
}
