import CoreGraphics
import Foundation

extension Playground {
    /// After this long without keyboard or mouse input, pets nap until the user comes back.
    static let awayAfter = 300.0

    /// Seconds since the user last touched the keyboard or mouse (reported by the app every tick).
    public mutating func setUserIdle(_ seconds: Double) {
        userIdle = seconds
    }

    mutating func awayRules() {
        if userIdle >= Self.awayAfter {
            userAway = true
            for i in pets.indices where pets[i].role == .own && pets[i].visible && pets[i].body.isGrounded {
                if pets[i].brain.isSleeping { pets[i].brain.sleepIndefinitely() } else { pets[i].fallAsleep(indefinitely: true) }
            }
        } else if userAway && userIdle < 2 {
            userAway = false
            for i in pets.indices where pets[i].role == .own && pets[i].visible && pets[i].brain.isSleeping {
                let facing: Direction = lastCursor.x > pets[i].body.position.x ? .right : .left
                let greet = Script(anim: .greet, facing: facing, hearts: 1, end: .animationFinished, priority: 2)
                if pets[i].interrupt(with: Script(anim: .wake, facing: facing, end: .animationFinished, priority: 2,
                                                  then: .script(greet))) {
                    pets[i].brain.noteInteraction()
                    feel(.happy, i)
                }
            }
        }
    }
}
