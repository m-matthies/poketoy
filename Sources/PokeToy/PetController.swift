import AppKit
import PokeToyCore

/// Draws one pet (own or wild) from its `PetActor` and forwards mouse input to the model.
@MainActor
final class PetController: PetViewDelegate {
    let id: UUID
    private let sprites: SpriteSet
    private unowned let model: AppModel
    private let interactive: Bool
    private let window = PetWindow()
    private var drag = DragTracker()
    private var pressing = false
    private var wanted = false

    init(id: UUID, sprites: SpriteSet, model: AppModel, interactive: Bool) {
        self.id = id
        self.sprites = sprites
        self.model = model
        self.interactive = interactive
        window.petView.delegate = self
    }

    func show() { wanted = true }

    func hide() {
        wanted = false
        window.orderOut(nil)
    }

    func close() { window.close() }

    func render(_ actor: PetActor, cursor: CGPoint) {
        if pressing, NSEvent.pressedMouseButtons & 1 == 0 {
            // The mouse-up never reached us (e.g. a system gesture took over mid-drag).
            if actor.brain.state == .dragged { petViewDragEnded() } else { model.handle(.released, pet: id) }
            pressing = false
        }
        guard wanted, actor.visible else {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        let pose = actor.pose
        let animation = sprites.animation(pose.anim)
        let frames = animation.frames(facing: pose.facing)
        window.render(sprite: frames[actor.animator.frameIndex % frames.count],
                      footPadding: animation.footPadding(facing: pose.facing),
                      hearts: pose.hearts, feet: actor.body.position, scale: actor.scale)
        if !window.isVisible { window.orderFrontRegardless() }
        // Clicks pass through to other apps except over the sprite's own pixels.
        window.ignoresMouseEvents = !interactive || (!pressing && !window.hitsSprite(at: cursor))
    }

    // MARK: PetViewDelegate

    func petViewPressed() {
        pressing = true
        model.handle(.pressed, pet: id)
    }

    func petViewClicked() {
        pressing = false
        model.handle(.click, pet: id)
    }

    func petViewDragBegan(at point: CGPoint) {
        model.handle(.dragBegan, pet: id)
        drag.begin(at: point, objectPosition: model.playground.pet(id)?.body.position ?? point)
    }

    func petViewDragMoved(to point: CGPoint) {
        model.movePet(id, to: drag.move(to: point))
    }

    func petViewDragEnded() {
        pressing = false
        model.handle(.dragEnded(velocity: drag.releaseVelocity(cap: 1500)), pet: id)
    }
}
