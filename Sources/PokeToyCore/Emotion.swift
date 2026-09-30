/// A feeling a pet shows in a bubble above its head.
public enum Emotion: CaseIterable, Sendable {
    case happy, joyous, sad, angry, surprised, pain, dizzy

    /// SpriteCollab portrait names to try, best first; every Pokémon has "Normal".
    public var portraitNames: [String] {
        switch self {
        case .happy: return ["Happy", "Joyous", "Normal"]
        case .joyous: return ["Joyous", "Happy", "Normal"]
        case .sad: return ["Sad", "Teary-Eyed", "Crying", "Normal"]
        case .angry: return ["Angry", "Determined", "Normal"]
        case .surprised: return ["Surprised", "Stunned", "Normal"]
        case .pain: return ["Pain", "Sad", "Normal"]
        case .dizzy: return ["Dizzy", "Stunned", "Pain", "Normal"]
        }
    }

    /// Shown when no portrait could be loaded.
    public var emoji: String {
        switch self {
        case .happy: return "😊"
        case .joyous: return "😄"
        case .sad: return "😢"
        case .angry: return "😠"
        case .surprised: return "😮"
        case .pain: return "😣"
        case .dizzy: return "😵"
        }
    }
}
