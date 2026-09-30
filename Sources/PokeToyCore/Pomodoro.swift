import Foundation

/// Pomodoro preferences: phase lengths, the long-break rhythm, what starts by itself, and how you're told.
public struct PomodoroOptions: Codable, Equatable, Sendable {
    public static let focusRange = 1...120
    public static let breakRange = 1...60
    public static let rhythmRange = 2...10
    public static let evolveRange = 1...1000

    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    /// A long break after this many focuses.
    public var focusesPerLongBreak = 4
    public var autoStartBreaks = true
    public var autoStartFocus = false
    public var notifications = true
    public var sound = true
    /// Pets come to the pointer and hop about when a focus or break ends.
    public var seekAttention = true
    /// Focus sessions a pet must finish (with its treats) before it can evolve.
    public var focusSessionsToEvolve = 50

    public init() {}

    public func duration(of phase: Pomodoro.Phase) -> Double {
        switch phase {
        case .focus: return Double(focusMinutes * 60)
        case .shortBreak: return Double(shortBreakMinutes * 60)
        case .longBreak: return Double(longBreakMinutes * 60)
        }
    }

    public func minutes(of phase: Pomodoro.Phase) -> Int {
        Int(duration(of: phase) / 60)
    }

    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, focusesPerLongBreak, autoStartBreaks, autoStartFocus,
             notifications, sound, seekAttention, focusSessionsToEvolve
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PomodoroOptions()
        func int(_ key: CodingKeys, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            min(max((try? c.decodeIfPresent(Int.self, forKey: key)) ?? fallback, range.lowerBound), range.upperBound)
        }
        func bool(_ key: CodingKeys, _ fallback: Bool) -> Bool {
            (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? fallback
        }
        focusMinutes = int(.focusMinutes, d.focusMinutes, Self.focusRange)
        shortBreakMinutes = int(.shortBreakMinutes, d.shortBreakMinutes, Self.breakRange)
        longBreakMinutes = int(.longBreakMinutes, d.longBreakMinutes, Self.breakRange)
        focusesPerLongBreak = int(.focusesPerLongBreak, d.focusesPerLongBreak, Self.rhythmRange)
        autoStartBreaks = bool(.autoStartBreaks, d.autoStartBreaks)
        autoStartFocus = bool(.autoStartFocus, d.autoStartFocus)
        notifications = bool(.notifications, d.notifications)
        sound = bool(.sound, d.sound)
        seekAttention = bool(.seekAttention, d.seekAttention)
        focusSessionsToEvolve = int(.focusSessionsToEvolve, d.focusSessionsToEvolve, Self.evolveRange)
    }
}

/// A Pomodoro timer set on a pet: focus, then a short break (a long one after every few focuses), as set in
/// `PomodoroOptions`. What comes next starts by itself, or waits to be started (`phase` is then the one to start).
public struct Pomodoro: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, CaseIterable, Sendable {
        case focus, shortBreak, longBreak

        public var duration: Double {
            switch self {
            case .focus: return 25 * 60
            case .shortBreak: return 5 * 60
            case .longBreak: return 15 * 60
            }
        }

        public var title: String {
            switch self {
            case .focus: return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak: return "Long Break"
            }
        }

        public var isBreak: Bool { self != .focus }
    }

    public enum State: Codable, Equatable, Sendable {
        case running(endsAt: Date)
        case paused(remaining: Double)
        /// A phase is over and the next one (`phase`) hasn't been started.
        case waiting
    }

    public enum Outcome: Equatable, Sendable {
        /// A focus finished; `next` (a break) comes now — started, or waiting to be.
        case focusDone(next: Phase)
        case breakDone
    }


    /// The pet showing the timer.
    public var petID: UUID
    public private(set) var phase: Phase
    public private(set) var state: State
    /// Focus sessions finished since the last long break.
    public private(set) var focusesDone: Int

    public init(petID: UUID, phase: Phase, now: Date, focusesDone: Int = 0, options: PomodoroOptions = PomodoroOptions()) {
        self.petID = petID
        self.phase = phase
        state = .running(endsAt: now.addingTimeInterval(options.duration(of: phase)))
        self.focusesDone = focusesDone
    }

    public var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    public var isWaiting: Bool { state == .waiting }

    /// Seconds left in the current phase (0 while waiting).
    public func remaining(at now: Date) -> Double {
        switch state {
        case .running(let endsAt): return max(0, endsAt.timeIntervalSince(now))
        case .paused(let remaining): return remaining
        case .waiting: return 0
        }
    }

    public mutating func start(_ phase: Phase, at now: Date, options: PomodoroOptions = PomodoroOptions()) {
        self.phase = phase
        state = .running(endsAt: now.addingTimeInterval(options.duration(of: phase)))
    }

    public mutating func pause(at now: Date) {
        guard case .running = state else { return }
        state = .paused(remaining: remaining(at: now))
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let remaining) = state else { return }
        state = .running(endsAt: now.addingTimeInterval(remaining))
    }

    /// Finishes the phase if its time is up (the break starts from `now`, e.g. after the Mac slept through the end).
    public mutating func advance(at now: Date, options: PomodoroOptions = PomodoroOptions()) -> Outcome? {
        guard case .running(let endsAt) = state, now >= endsAt else { return nil }
        return finish(at: now, options: options)
    }

    /// Ends the current phase right away.
    public mutating func skip(at now: Date, options: PomodoroOptions = PomodoroOptions()) -> Outcome? {
        guard !isWaiting else { return nil }
        return finish(at: now, options: options)
    }

    private mutating func finish(at now: Date, options: PomodoroOptions) -> Outcome {
        switch phase {
        case .focus:
            focusesDone += 1
            let next: Phase = focusesDone >= options.focusesPerLongBreak ? .longBreak : .shortBreak
            startOrWait(next, autoStart: options.autoStartBreaks, at: now, options: options)
            return .focusDone(next: next)
        case .shortBreak, .longBreak:
            if phase == .longBreak { focusesDone = 0 }
            startOrWait(.focus, autoStart: options.autoStartFocus, at: now, options: options)
            return .breakDone
        }
    }

    private mutating func startOrWait(_ next: Phase, autoStart: Bool, at now: Date, options: PomodoroOptions) {
        if autoStart {
            start(next, at: now, options: options)
        } else {
            phase = next
            state = .waiting
        }
    }

    /// "12:05"
    public static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
