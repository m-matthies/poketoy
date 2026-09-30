import Foundation

/// A named session to start from a pet's menu: work (counts as a focus) or relax (a break).
/// The three built-ins (`focus`, `shortBreak`, `longBreak`) drive the automatic cycle: they can be renamed and
/// resized but not removed, and their kind is fixed.
public struct SessionPreset: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case work, relax
    }

    public static let builtInIDs = ["focus", "shortBreak", "longBreak"]

    public var id: String
    public var name: String
    public var minutes: Int
    public var kind: Kind

    public init(id: String, name: String, minutes: Int, kind: Kind) {
        self.id = id
        self.name = name
        self.minutes = minutes
        self.kind = kind
    }

    public var isBuiltIn: Bool { Self.builtInIDs.contains(id) }

    /// The timer phase this session runs as.
    public var phase: Pomodoro.Phase {
        id == "longBreak" ? .longBreak : kind == .work ? .focus : .shortBreak
    }

    public static func builtIn(_ phase: Pomodoro.Phase, minutes: Int) -> SessionPreset {
        SessionPreset(id: phase.rawValue, name: phase.title, minutes: minutes, kind: phase == .focus ? .work : .relax)
    }
}

/// Pomodoro preferences: sessions (with the cycle's lengths), the long-break rhythm, what starts by itself, and how
/// you're told.
public struct PomodoroOptions: Codable, Equatable, Sendable {
    public static let focusRange = 1...120
    public static let breakRange = 1...60
    public static let sessionRange = 1...180
    public static let rhythmRange = 2...10
    public static let evolveRange = 1...1000

    /// The built-in Focus, Short Break and Long Break first, then the player's own.
    public var sessions: [SessionPreset] = [
        .builtIn(.focus, minutes: 25), .builtIn(.shortBreak, minutes: 5), .builtIn(.longBreak, minutes: 15),
    ]
    /// A long break after this many focuses.
    public var focusesPerLongBreak = 4
    public var autoStartBreaks = true
    public var autoStartFocus = false
    public var notifications = true
    public var sound = true
    /// Pets come to the pointer and hop about when a focus or break ends.
    public var seekAttention = true
    /// Focus sessions a pet must finish (with its treats and a best friend) before it can evolve.
    public var focusSessionsToEvolve = 50

    public init() {}

    public var focusMinutes: Int {
        get { builtIn(.focus).minutes }
        set { setMinutes(newValue, of: .focus) }
    }

    public var shortBreakMinutes: Int {
        get { builtIn(.shortBreak).minutes }
        set { setMinutes(newValue, of: .shortBreak) }
    }

    public var longBreakMinutes: Int {
        get { builtIn(.longBreak).minutes }
        set { setMinutes(newValue, of: .longBreak) }
    }

    public func duration(of phase: Pomodoro.Phase) -> Double {
        Double(builtIn(phase).minutes * 60)
    }

    public func minutes(of phase: Pomodoro.Phase) -> Int {
        builtIn(phase).minutes
    }

    /// What the player calls this part of the cycle ("Focus", or their own name for it).
    public func name(of phase: Pomodoro.Phase) -> String {
        builtIn(phase).name
    }

    public func session(_ id: String) -> SessionPreset? {
        sessions.first { $0.id == id }
    }

    /// Adds a session of the player's own; returns its id.
    @discardableResult
    public mutating func addSession(name: String, minutes: Int, kind: SessionPreset.Kind) -> String {
        let id = UUID().uuidString
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions.append(SessionPreset(id: id, name: trimmed.isEmpty ? (kind == .work ? "Work" : "Relax") : trimmed,
                                      minutes: Self.clamp(minutes, Self.sessionRange), kind: kind))
        return id
    }

    /// Renames a session (a blank name changes nothing).
    public mutating func rename(session id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].name = trimmed
    }

    public mutating func setMinutes(_ minutes: Int, ofSession id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].minutes = Self.clamp(minutes, Self.range(for: sessions[index]))
    }

    /// Changes whether one of the player's own sessions is work or relax (built-ins keep theirs).
    public mutating func setKind(_ kind: SessionPreset.Kind, ofSession id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), !sessions[index].isBuiltIn else { return }
        sessions[index].kind = kind
    }

    /// Removes one of the player's own sessions (built-ins stay).
    public mutating func removeSession(_ id: String) {
        sessions.removeAll { $0.id == id && !$0.isBuiltIn }
    }

    public static func range(for session: SessionPreset) -> ClosedRange<Int> {
        switch session.id {
        case "focus": return focusRange
        case "shortBreak", "longBreak": return breakRange
        default: return sessionRange
        }
    }

    private func builtIn(_ phase: Pomodoro.Phase) -> SessionPreset {
        session(phase.rawValue) ?? .builtIn(phase, minutes: Int(phase.duration / 60))
    }

    private mutating func setMinutes(_ minutes: Int, of phase: Pomodoro.Phase) {
        setMinutes(minutes, ofSession: phase.rawValue)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Built-ins first (always there, kind fixed, blank names restored), then the player's own sessions with a
    /// name, each id once.
    static func normalized(_ list: [SessionPreset], legacy: [Pomodoro.Phase: Int]) -> [SessionPreset] {
        var seen = Set<String>()
        let unique = list.filter { seen.insert($0.id).inserted }
        var result: [SessionPreset] = []
        for phase in [Pomodoro.Phase.focus, .shortBreak, .longBreak] {
            var preset = SessionPreset.builtIn(phase, minutes: legacy[phase] ?? Int(phase.duration / 60))
            if let saved = unique.first(where: { $0.id == phase.rawValue }) {
                let name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { preset.name = name }
                preset.minutes = saved.minutes
            }
            preset.minutes = clamp(preset.minutes, range(for: preset))
            result.append(preset)
        }
        for var preset in unique where !preset.isBuiltIn {
            preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !preset.name.isEmpty else { continue }
            preset.minutes = clamp(preset.minutes, sessionRange)
            result.append(preset)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case sessions, focusMinutes, shortBreakMinutes, longBreakMinutes, focusesPerLongBreak, autoStartBreaks,
             autoStartFocus, notifications, sound, seekAttention, focusSessionsToEvolve
    }

    /// A session that may fail to decode (then it's skipped).
    private struct LossyPreset: Decodable {
        let preset: SessionPreset?
        init(from decoder: Decoder) throws {
            preset = try? SessionPreset(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PomodoroOptions()
        func int(_ key: CodingKeys, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            Self.clamp((try? c.decodeIfPresent(Int.self, forKey: key)) ?? fallback, range)
        }
        func bool(_ key: CodingKeys, _ fallback: Bool) -> Bool {
            (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? fallback
        }
        // Earlier versions stored only the three lengths.
        var legacy: [Pomodoro.Phase: Int] = [:]
        for (phase, key) in [(Pomodoro.Phase.focus, CodingKeys.focusMinutes), (.shortBreak, .shortBreakMinutes),
                             (.longBreak, .longBreakMinutes)] {
            if let minutes = try? c.decodeIfPresent(Int.self, forKey: key) { legacy[phase] = minutes }
        }
        let saved = ((try? c.decodeIfPresent([LossyPreset].self, forKey: .sessions)) ?? nil)?.compactMap(\.preset) ?? []
        sessions = Self.normalized(saved, legacy: legacy)
        focusesPerLongBreak = int(.focusesPerLongBreak, d.focusesPerLongBreak, Self.rhythmRange)
        autoStartBreaks = bool(.autoStartBreaks, d.autoStartBreaks)
        autoStartFocus = bool(.autoStartFocus, d.autoStartFocus)
        notifications = bool(.notifications, d.notifications)
        sound = bool(.sound, d.sound)
        seekAttention = bool(.seekAttention, d.seekAttention)
        focusSessionsToEvolve = int(.focusSessionsToEvolve, d.focusSessionsToEvolve, Self.evolveRange)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(focusesPerLongBreak, forKey: .focusesPerLongBreak)
        try c.encode(autoStartBreaks, forKey: .autoStartBreaks)
        try c.encode(autoStartFocus, forKey: .autoStartFocus)
        try c.encode(notifications, forKey: .notifications)
        try c.encode(sound, forKey: .sound)
        try c.encode(seekAttention, forKey: .seekAttention)
        try c.encode(focusSessionsToEvolve, forKey: .focusSessionsToEvolve)
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
    /// What the running (or next) session is called: "Focus", "Deep Work"…
    public private(set) var label: String
    /// What the player is working on, if they named it ("Write the report").
    public private(set) var task: String?

    public init(petID: UUID, phase: Phase, now: Date, focusesDone: Int = 0, options: PomodoroOptions = PomodoroOptions()) {
        self.petID = petID
        self.phase = phase
        state = .running(endsAt: now.addingTimeInterval(options.duration(of: phase)))
        self.focusesDone = focusesDone
        label = options.name(of: phase)
    }

    /// A timer running one of the named sessions (a work session counts as a focus, a relax one as a break).
    public init(petID: UUID, session: SessionPreset, now: Date, focusesDone: Int = 0,
                options: PomodoroOptions = PomodoroOptions()) {
        self.init(petID: petID, phase: session.phase, now: now, focusesDone: focusesDone, options: options)
        start(session, at: now)
    }

    /// A timer that isn't running yet: the next focus waits to be started (e.g. a task was named first).
    public static func waiting(petID: UUID, options: PomodoroOptions = PomodoroOptions()) -> Pomodoro {
        var timer = Pomodoro(petID: petID, phase: .focus, now: Date(), options: options)
        timer.state = .waiting
        return timer
    }

    /// Names the task (a blank name clears it).
    public mutating func setTask(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        task = trimmed.isEmpty ? nil : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case petID, phase, state, focusesDone, label, task
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        petID = try c.decode(UUID.self, forKey: .petID)
        phase = try c.decode(Phase.self, forKey: .phase)
        state = try c.decode(State.self, forKey: .state)
        focusesDone = try c.decode(Int.self, forKey: .focusesDone)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? phase.title  // saved before names existed
        task = try? c.decodeIfPresent(String.self, forKey: .task)
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
        label = options.name(of: phase)
        state = .running(endsAt: now.addingTimeInterval(options.duration(of: phase)))
    }

    public mutating func start(_ session: SessionPreset, at now: Date) {
        phase = session.phase
        label = session.name
        state = .running(endsAt: now.addingTimeInterval(Double(session.minutes * 60)))
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
            label = options.name(of: next)
            state = .waiting
        }
    }

    /// "12:05"
    public static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
