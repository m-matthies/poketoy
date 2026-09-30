import CoreGraphics
import Foundation

extension Playground {
    /// Above every other behaviour, so a held pet stays put.
    static let holdPriority = 9

    /// Keeps a pet where it is — standing still, facing the way it faces — until `letGo` (e.g. while its menu or task
    /// editor is open). A sleeping pet sleeps on; one in mid-air holds once it lands.
    public mutating func hold(_ id: UUID) {
        held.insert(id)
        holdRules()
    }

    public mutating func letGo(_ id: UUID) {
        held.remove(id)
        if let i = index(of: id), pets[i].brain.script?.priority == Self.holdPriority { pets[i].endScript() }
    }

    mutating func holdRules() {
        for id in held {
            guard let i = index(of: id) else {
                held.remove(id)
                continue
            }
            guard !pets[i].brain.isSleeping, pets[i].body.isGrounded,
                  pets[i].brain.script?.priority != Self.holdPriority else { continue }
            let still = Script(anim: .idle, facing: pets[i].brain.pose.facing, end: .after(3600), priority: Self.holdPriority)
            if pets[i].perform(still) { pets[i].body.velocity.dx = 0 }
        }
    }
}
