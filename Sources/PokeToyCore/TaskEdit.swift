import Foundation

/// What a pet's timer was when its task editor opened, so saving only changes what the player changed.
public struct TaskEditSnapshot: Equatable, Sendable {
    public let hadTimer: Bool
    public let phase: Pomodoro.Phase?
    public let waiting: Bool
    /// The minutes the editor showed as time left (nil when nothing was running).
    public let minutesShown: Int?

    public init(timer: Pomodoro?, now: Date) {
        hadTimer = timer != nil
        phase = timer?.phase
        waiting = timer?.isWaiting ?? false
        minutesShown = timer.flatMap { $0.isWaiting ? nil : Int(($0.remaining(at: now) / 60).rounded(.up)) }
    }
}

/// Saving the task editor above a pet.
public enum TaskEdit {
    public enum Commit: Sendable {
        /// Return: save, and start a focus of the given length when none is running.
        case returnKey
        /// Clicked elsewhere or PokeToy quit: save what was typed, start nothing.
        case elsewhere
    }

    /// The pet's timer after saving `name` and `minutes`: the name is always kept (a blank one clears it); the minutes
    /// start a focus only on Return with no timer or a focus waiting, and set the time left only if they were changed
    /// and the timer is still in the phase it was in when the editor opened.
    public static func apply(name: String, minutes: Int?, snapshot: TaskEditSnapshot, to timer: Pomodoro?, petID: UUID,
                             committed: Commit, now: Date, options: PomodoroOptions) -> (timer: Pomodoro?, started: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard timer != nil || committed == .returnKey || !trimmed.isEmpty else { return (nil, false) }
        var edited = timer ?? Pomodoro.waiting(petID: petID, options: options)
        edited.setTask(trimmed)
        let unchanged = snapshot.hadTimer == (timer != nil) && snapshot.phase == timer?.phase
            && snapshot.waiting == (timer?.isWaiting ?? false)
        guard unchanged, let minutes else { return (edited, false) }
        if edited.isWaiting {
            guard edited.phase == .focus, committed == .returnKey else { return (edited, false) }
            edited.startFocus(minutes: minutes, at: now, options: options)
            return (edited, true)
        }
        if minutes != snapshot.minutesShown { edited.setRemaining(minutes: minutes, at: now) }
        return (edited, false)
    }
}
