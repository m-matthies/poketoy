import Foundation

/// A Pomodoro timer set on a pet: 25 minutes of focus, then a 5-minute break (15 after every fourth focus).
/// A finished focus starts its break at once; a finished break waits for the next focus to be started.
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
        /// A break is over; the next focus hasn't been started.
        case waiting
    }

    public enum Outcome: Equatable, Sendable {
        /// A focus finished and `next` (a break) has started.
        case focusDone(next: Phase)
        case breakDone
    }

    public static let focusesPerLongBreak = 4

    /// The pet showing the timer.
    public var petID: UUID
    public private(set) var phase: Phase
    public private(set) var state: State
    /// Focus sessions finished since the last long break.
    public private(set) var focusesDone: Int

    public init(petID: UUID, phase: Phase, now: Date, focusesDone: Int = 0) {
        self.petID = petID
        self.phase = phase
        state = .running(endsAt: now.addingTimeInterval(phase.duration))
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

    public mutating func start(_ phase: Phase, at now: Date) {
        self.phase = phase
        state = .running(endsAt: now.addingTimeInterval(phase.duration))
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
    public mutating func advance(at now: Date) -> Outcome? {
        guard case .running(let endsAt) = state, now >= endsAt else { return nil }
        return finish(at: now)
    }

    /// Ends the current phase right away.
    public mutating func skip(at now: Date) -> Outcome? {
        guard !isWaiting else { return nil }
        return finish(at: now)
    }

    private mutating func finish(at now: Date) -> Outcome {
        switch phase {
        case .focus:
            focusesDone += 1
            let next: Phase = focusesDone >= Self.focusesPerLongBreak ? .longBreak : .shortBreak
            start(next, at: now)
            return .focusDone(next: next)
        case .shortBreak, .longBreak:
            if phase == .longBreak { focusesDone = 0 }
            state = .waiting
            return .breakDone
        }
    }

    /// "12:05"
    public static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
