/// What the pet is visibly doing. Each kind maps to PMD animation names in order of preference.
public enum PetAnim: CaseIterable, Sendable {
    case idle, walk, sleep, react, dangle, land

    public var candidates: [String] {
        switch self {
        case .idle: return ["Idle", "Walk"]
        case .walk: return ["Walk", "Idle"]
        case .sleep: return ["Sleep", "EventSleep", "Laying", "Idle", "Walk"]
        case .react: return ["Hop", "Pose", "Idle", "Walk"]
        case .dangle: return ["Hurt", "Idle", "Walk"]
        case .land: return ["Hurt", "Idle", "Walk"]
        }
    }

    /// Non-looping animations play once and then report `Animator.finished`.
    public var loops: Bool {
        switch self {
        case .react, .land: return false
        default: return true
        }
    }
}
