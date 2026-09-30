import AppKit
import PokeToyCore

/// A treat in its own floating panel; it can be pressed, dragged and thrown like a pet.
@MainActor
final class ItemController: PetViewDelegate {
    let id: UUID
    private unowned let model: AppModel
    private let window = PetWindow()
    private var drag = DragTracker()
    private var pressing = false
    private var wanted = true

    init(id: UUID, model: AppModel) {
        self.id = id
        self.model = model
        window.petView.delegate = self
    }

    func show() { wanted = true }

    func hide() {
        wanted = false
        window.orderOut(nil)
    }

    func close() { window.close() }

    func render(_ item: Item, cursor: CGPoint, scale: CGFloat) {
        if pressing, NSEvent.pressedMouseButtons & 1 == 0 {
            model.handle(.released, item: id)
            pressing = false
        }
        guard wanted else {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        window.render(sprite: ItemArt.frame(for: item.kind), footPadding: 0, hearts: 0, feet: item.body.position, scale: scale)
        if !window.isVisible { window.orderFrontRegardless() }
        window.ignoresMouseEvents = !pressing && !window.hitsSprite(at: cursor)
    }

    // MARK: PetViewDelegate

    func petViewPressed() {
        pressing = true
        model.handle(.pressed, item: id)
    }

    func petViewClicked() {
        pressing = false
        model.handle(.released, item: id)
    }

    func petViewDragBegan(at point: CGPoint) {
        model.handle(.dragBegan, item: id)
        let position = model.playground.items.first { $0.id == id }?.body.position ?? point
        drag.begin(at: point, objectPosition: position)
    }

    func petViewDragMoved(to point: CGPoint) {
        model.moveItem(id, to: drag.move(to: point))
    }

    func petViewDragEnded() {
        pressing = false
        model.handle(.dragEnded(velocity: drag.releaseVelocity(cap: 1500)), item: id)
    }
}
