/// What the pet is visibly doing. Each kind maps to PMD animation names in order of preference.
public enum PetAnim: CaseIterable, Sendable {
    case idle, walk, sleep, react, dangle, land, eat, greet, attack, sad, sit, cheer, wake

    public var candidates: [String] {
        switch self {
        case .idle: return ["Idle", "Walk"]
        case .walk: return ["Walk", "Idle"]
        case .sleep: return ["Sleep", "EventSleep", "Laying", "Idle", "Walk"]
        case .react: return ["Hop", "Pose", "Idle", "Walk"]
        case .dangle: return ["Hurt", "Idle", "Walk"]
        case .land: return ["Hurt", "Idle", "Walk"]
        case .eat: return ["Eat", "Nod", "Idle", "Walk"]
        case .greet: return ["Nod", "Pose", "Hop", "Idle", "Walk"]
        case .attack: return ["Attack", "Swing", "Hop", "Walk"]
        case .sad: return ["Cringe", "Pain", "Hurt", "Idle", "Walk"]
        case .sit: return ["Sit", "Idle", "Walk"]
        case .cheer: return ["Hop", "Pose", "Idle", "Walk"]
        case .wake: return ["Wake", "Idle", "Walk"]
        }
    }

    /// Non-looping animations play once and then report `Animator.finished`.
    public var loops: Bool {
        switch self {
        case .react, .land, .greet, .attack, .sad, .cheer, .wake: return false
        default: return true
        }
    }
}
