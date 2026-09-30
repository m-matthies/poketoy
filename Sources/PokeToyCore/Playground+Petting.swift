import CoreGraphics
import Foundation

/// Tracks the cursor rubbing back and forth over one pet.
struct StrokeTracker: Sendable {
    var lastX: CGFloat
    var direction: CGFloat = 0
    /// Where the cursor last turned around.
    var turnX: CGFloat
    var reversals: [Double] = []
    var cooldownUntil: Double = 0

    init(x: CGFloat) {
        lastX = x
        turnX = x
    }
}

extension Playground {
    static let strokeReversals = 3
    static let strokeWindow = 1.5
    static let strokeMinSwing: CGFloat = 6
    static let strokeCooldown = 3.0
    static let annoyingClicks = 5
    static let annoyingClickWindow = 4.0

    /// The cursor is over pet `id` at `cursorX` with no button pressed. Rubbing back and forth strokes it.
    public mutating func stroke(pet id: UUID, cursorX: CGFloat) {
        guard let i = index(of: id), pets[i].visible, pets[i].role == .own else { return }
        if pets[i].brain.state == .held || pets[i].brain.state == .dragged {
            strokes[id] = nil
            return
        }
        var tracker = strokes[id] ?? StrokeTracker(x: cursorX)
        let dx = cursorX - tracker.lastX
        if abs(dx) >= 1 {
            let direction: CGFloat = dx > 0 ? 1 : -1
            if tracker.direction != 0 && direction != tracker.direction {
                if abs(tracker.lastX - tracker.turnX) >= Self.strokeMinSwing { tracker.reversals.append(clock) }
                tracker.turnX = tracker.lastX
            }
            tracker.direction = direction
        }
        tracker.lastX = cursorX
        tracker.reversals.removeAll { clock - $0 > Self.strokeWindow }
        if tracker.reversals.count >= Self.strokeReversals && clock >= tracker.cooldownUntil {
            tracker.reversals = []
            tracker.cooldownUntil = clock + Self.strokeCooldown
            if pets[i].petted() { feel(.happy, i) }
        }
        strokes[id] = tracker
    }

    /// The cursor left pet `id`: an unfinished stroke starts over next time.
    public mutating func strokeEnded(pet id: UUID) {
        strokes[id] = nil
    }

    /// Records a click on own pet `i`. Returns true if the click is swallowed because the pet is (now) annoyed.
    mutating func noteClick(_ i: Int) -> Bool {
        let id = pets[i].id
        var times = (clickTimes[id] ?? []).filter { clock - $0 <= Self.annoyingClickWindow }
        times.append(clock)
        guard times.count >= Self.annoyingClicks else {
            clickTimes[id] = times
            return false
        }
        clickTimes[id] = []
        return annoy(i)
    }

    /// Glares at the cursor with an angry look, then storms off away from it.
    private mutating func annoy(_ i: Int) -> Bool {
        let x = pets[i].body.position.x
        let away: CGFloat = lastCursor.x > x ? -1 : 1
        let target = clampOnSurface(x + away * 250, pet: i, world: lastWorld)
        if pets[i].brain.state == .held { pets[i].handle(.released) }  // the mouse went down for this click
        let stormOff = Script(anim: .walk, moveTo: target, speed: PetBrain.walkSpeed * 1.6, end: .arrived, priority: 3)
        let glare = Script(anim: .shoot, facing: away > 0 ? .left : .right, end: .animationFinished, priority: 3,
                           then: .script(stormOff))
        guard pets[i].interrupt(with: glare) else { return false }
        annoyedUntil[pets[i].id] = clock + Self.annoyingClickWindow
        feel(.angry, i)
        return true
    }
}
