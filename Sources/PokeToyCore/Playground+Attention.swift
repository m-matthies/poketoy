import CoreGraphics
import Foundation

/// A pet trying to get the user's attention (a Pomodoro phase just ended).
struct AttentionSeeker: Sendable {
    var remaining: Double
    /// Seconds until the next hop-and-call at the cursor.
    var nextCall: Double = 0
}

extension Playground {
    /// Pets give up trying to get your attention after this long.
    public static let attentionTime = 60.0
    static let attentionCallInterval = 1.6

    public var isSeekingAttention: Bool { !attention.isEmpty }

    /// `id` — and with `everyone`, all your other pets — wake up, come to the mouse pointer (jumping up to it if
    /// need be) and hop about calling out until one of them is clicked or a minute has passed.
    public mutating func seekAttention(_ id: UUID, everyone: Bool = true) {
        let seekers = pets.indices.filter { pets[$0].role == .own && pets[$0].visible && (everyone || pets[$0].id == id) }
        for i in seekers {
            attention[pets[i].id] = AttentionSeeker(remaining: Self.attentionTime)
            pets[i].brain.noteInteraction()
            if pets[i].brain.isSleeping {
                let facing: Direction = lastCursor.x > pets[i].body.position.x ? .right : .left
                pets[i].interrupt(with: Script(anim: .wake, facing: facing, end: .animationFinished, priority: 2))
            }
        }
    }

    /// The user noticed: `id` stops trying (it was looked at, or its timer was used); with no id, all of them do
    /// (a seeking pet was clicked).
    public mutating func stopSeekingAttention(_ id: UUID? = nil) {
        if let id { attention[id] = nil } else { attention = [:] }
    }

    /// Seekers follow the cursor (see `updateBrain`); once there, they hop and call out every so often.
    mutating func attentionRules(dt: Double) {
        for (id, var seeker) in attention {
            seeker.remaining -= dt
            seeker.nextCall -= dt
            guard seeker.remaining > 0, let i = index(of: id), pets[i].visible else {
                attention[id] = nil
                continue
            }
            let pet = pets[i]
            let nearCursor = abs(lastCursor.x - pet.body.position.x) < 60 && abs(lastCursor.y - pet.body.position.y) < 160
            if nearCursor, seeker.nextCall <= 0, pet.body.isGrounded, pet.brain.script == nil {
                let facing: Direction = lastCursor.x > pet.body.position.x ? .right : .left
                if pets[i].perform(Script(anim: .react, facing: facing, end: .animationFinished, priority: 2)) {
                    feel(rng.unit() < 0.5 ? .surprised : .joyous, i)
                    seeker.nextCall = Self.attentionCallInterval
                }
            }
            attention[id] = seeker
        }
    }
}
