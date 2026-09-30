import AppKit
import PokeToyCore

/// One on-screen pet: its behavior, physics body, animation state and window.
@MainActor
final class PetController: PetViewDelegate {
    let id: UUID
    var scale: CGFloat
    var position: CGPoint { body.position }

    private let sprites: SpriteSet
    private var brain = PetBrain(seed: .random(in: .min ... .max))
    private var body: Body
    private var animator = Animator()
    private var poseToken = -1
    private let window = PetWindow()
    private var dragOffset = CGVector.zero
    private var dragSamples: [(time: CFTimeInterval, point: CGPoint)] = []

    init(record: PetRecord, sprites: SpriteSet, world: World, scale: Int) {
        id = record.id
        self.sprites = sprites
        self.scale = CGFloat(scale)
        if let saved = record.position, world.isOnAnyScreen(saved, margin: 0) {
            body = Body(position: saved)
        } else {
            body = Body(position: world.spawnPoint(fraction: .random(in: 0.2...0.8)))
        }
        window.petView.delegate = self
    }

    func show() { window.orderFrontRegardless() }
    func hide() { window.orderOut(nil) }
    func close() { window.close() }

    func tick(dt: Double, world: World, cursor: CGPoint, mode: CursorMode) {
        let finished = animator.finished && animator.kind == brain.pose.anim && poseToken == brain.pose.token
        let halfWidth = CGFloat(sprites.animation(brain.pose.anim).info.frameWidth) * scale * 0.3
        brain.update(BrainContext(dt: dt, world: world, cursor: cursor, cursorMode: mode,
                                  halfWidth: halfWidth, animationFinished: finished), body: &body)
        if brain.state != .dragged {
            Physics.step(&body, dt: CGFloat(dt), world: world)
            if !world.isOnAnyScreen(body.position, margin: 200) {
                body = Body(position: world.spawnPoint(fraction: 0.5))  // lost off-screen: drop back in
                brain.handle(.dragEnded(velocity: .zero), body: &body)
            }
        }

        let pose = brain.pose
        animator.play(pose.anim)
        if pose.token != poseToken {
            animator.restart()
            poseToken = pose.token
        }
        let animation = sprites.animation(pose.anim)
        animator.advance(dt: dt, durations: animation.durations)
        let frames = animation.frames(facing: pose.facing)
        window.render(sprite: frames[animator.frameIndex % frames.count],
                      footPadding: animation.footPadding(facing: pose.facing),
                      heart: pose.showHeart, feet: body.position, scale: scale)
        // Clicks pass through to other apps except over the sprite's own pixels.
        window.ignoresMouseEvents = brain.state != .dragged && !window.hitsSprite(at: cursor)
    }

    // MARK: PetViewDelegate

    func petViewClicked() {
        brain.handle(.click, body: &body)
    }

    func petViewDragBegan(at point: CGPoint) {
        brain.handle(.dragBegan, body: &body)
        dragOffset = CGVector(dx: body.position.x - point.x, dy: body.position.y - point.y)
        dragSamples = [(CACurrentMediaTime(), point)]
    }

    func petViewDragMoved(to point: CGPoint) {
        body.position = CGPoint(x: point.x + dragOffset.dx, y: point.y + dragOffset.dy)
        let now = CACurrentMediaTime()
        dragSamples.append((now, point))
        dragSamples.removeAll { $0.time < now - 0.1 }
    }

    func petViewDragEnded() {
        let now = CACurrentMediaTime()
        let recent = dragSamples.filter { $0.time >= now - 0.1 }
        var velocity = CGVector.zero
        if let first = recent.first, let last = recent.last, last.time - first.time > 0.01 {
            let elapsed = CGFloat(last.time - first.time)
            velocity = CGVector(dx: (last.point.x - first.point.x) / elapsed, dy: (last.point.y - first.point.y) / elapsed)
            let speed = hypot(velocity.dx, velocity.dy)
            if speed > 1500 {
                velocity.dx *= 1500 / speed
                velocity.dy *= 1500 / speed
            }
        }
        brain.handle(.dragEnded(velocity: velocity), body: &body)
    }
}
