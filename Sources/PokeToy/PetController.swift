import AppKit
import PokeToyCore

/// Draws one pet (own or wild) from its `PetActor` and forwards mouse input to the model.
@MainActor
final class PetController: PetViewDelegate {
    let id: UUID
    private var sprites: SpriteSet
    private unowned let model: AppModel
    private let interactive: Bool
    private let window = PetWindow()
    private var drag = DragTracker()
    private var pressing = false
    private var wanted = false
    /// Created the first time the pet shows an emotion.
    private lazy var bubble = BubbleWindow()
    private var bubbleCreated = false
    /// The Pomodoro countdown, made when this pet first carries a timer.
    private var badge: BadgeWindow?
    private var taskEditor: TaskEditorPanel?
    private var hovering = false
    private var bubbleEmotion: Emotion?
    private var bubbleUntil: CFTimeInterval = 0
    private var flashUntil: CFTimeInterval = 0
    private static let bubbleTime: CFTimeInterval = 2
    private static let flashTime: CFTimeInterval = 0.8

    init(id: UUID, sprites: SpriteSet, model: AppModel, interactive: Bool) {
        self.id = id
        self.sprites = sprites
        self.model = model
        self.interactive = interactive
        window.petView.delegate = self
    }

    func show() { wanted = true }

    func hide() {
        taskEditor?.commit()  // an open task editor goes too (keeping what was typed)
        wanted = false
        window.orderOut(nil)
        if bubbleCreated { bubble.orderOut(nil) }
        badge?.orderOut(nil)
    }

    func close() {
        window.close()
        if bubbleCreated { bubble.close() }
        badge?.close()
        taskEditor?.close()
    }

    /// Shows `emotion` in a bubble for a couple of seconds: the emoji now, the portrait once it's loaded.
    func showEmotion(_ emotion: Emotion) {
        bubbleEmotion = emotion
        bubbleUntil = CACurrentMediaTime() + Self.bubbleTime
        bubbleCreated = true
        bubble.show(image: nil, emoji: emotion.emoji)
    }

    func showPortrait(_ url: URL, for emotion: Emotion) {
        guard bubbleEmotion == emotion, CACurrentMediaTime() < bubbleUntil, let image = NSImage(contentsOf: url) else { return }
        bubble.show(image: image, emoji: emotion.emoji)
    }

    /// Glows white for a moment (evolving).
    func flash() {
        flashUntil = CACurrentMediaTime() + Self.flashTime
    }

    func replaceSprites(_ sprites: SpriteSet) {
        self.sprites = sprites
    }

    func render(_ actor: PetActor, cursor: CGPoint) {
        if pressing, NSEvent.pressedMouseButtons & 1 == 0 {
            // The mouse-up never reached us (e.g. a system gesture took over mid-drag).
            if actor.brain.state == .dragged { petViewDragEnded() } else { model.handle(.released, pet: id) }
            pressing = false
        }
        guard wanted, actor.visible else {
            if window.isVisible { window.orderOut(nil) }
            if bubbleCreated, bubble.isVisible { bubble.orderOut(nil) }
            if let badge, badge.isVisible { badge.orderOut(nil) }
            return
        }
        let now = CACurrentMediaTime()
        let pose = actor.pose
        let animation = sprites.animation(pose.anim)
        let frames = animation.frames(facing: pose.facing)
        window.render(sprite: frames[actor.animator.frameIndex % frames.count],
                      footPadding: animation.footPadding(facing: pose.facing),
                      hearts: pose.hearts, feet: actor.body.position, scale: actor.scale,
                      flash: CGFloat(max(0, (flashUntil - now) / Self.flashTime)))
        if !window.isVisible { window.orderFrontRegardless() }
        var bubbleBase = window.frame.maxY - 6
        if let text = model.pomodoroBadge(for: id) {
            let badge = self.badge ?? BadgeWindow()
            self.badge = badge
            badge.show(text)
            badge.place(centerX: actor.body.position.x, bottom: window.frame.maxY - 4, within: window.screen?.visibleFrame)
            bubbleBase = badge.frame.maxY  // the emotion bubble goes above the countdown
        } else if let badge, badge.isVisible {
            badge.orderOut(nil)
        }
        if now < bubbleUntil {
            bubble.place(tailAt: CGPoint(x: actor.body.position.x, y: bubbleBase),
                         within: window.screen?.visibleFrame)
        } else if bubbleCreated, bubble.isVisible {
            bubble.orderOut(nil)
        }
        // Rubbing the cursor over the pet (no button down) strokes it; leaving starts a stroke over.
        let overPet = interactive && !pressing && NSEvent.pressedMouseButtons == 0 && window.hitsSprite(at: cursor)
        if overPet {
            model.stroke(pet: id, cursorX: cursor.x)
        } else if hovering {
            model.strokeEnded(pet: id)
        }
        hovering = overPet
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

    func petViewContextMenu(_ event: NSEvent) {
        guard interactive, let menu = MenuBuilder(model: model).makePetMenu(for: id) else { return }
        model.noticed(pet: id)
        model.holdPet(id)  // it stays put while its menu is open
        NSMenu.popUpContextMenu(menu, with: event, for: window.petView)
        // The chosen item may have opened the task editor, which keeps holding the pet until it's done.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.taskEditor?.isEditing != true else { return }
                self.model.letGoPet(self.id)
            }
        }
    }

    /// What the pet looks like right now, and where (for the Poké Ball animation).
    func snapshot() -> (image: CGImage, rect: NSRect)? {
        window.spriteSnapshot
    }

    /// Saves a task still being typed (PokeToy is quitting).
    func commitTaskEdit() {
        taskEditor?.commit()
    }

    /// Opens the task editor right above the pet.
    func editTask() {
        let editor = taskEditor ?? TaskEditorPanel()
        taskEditor = editor
        let anchor = badge?.isVisible == true ? badge!.frame : window.frame
        let state = model.taskEditorState(for: id)
        let snapshot = TaskEditSnapshot(timer: model.timer(for: id), now: Date())  // what the editor was opened on
        model.holdPet(id)  // stays right under its editor
        editor.edit(text: state.task, minutes: state.minutes, unit: state.unit, hint: state.hint, above: anchor,
                    within: window.screen?.visibleFrame) { [weak self] result in
            guard let self else { return }
            self.model.letGoPet(self.id)
            guard let (name, minutes, commit) = result else { return }
            self.model.saveTask(name, minutes: minutes, snapshot: snapshot, committed: commit, on: self.id)
        }
    }

    func petViewDragEnded() {
        pressing = false
        model.handle(.dragEnded(velocity: drag.releaseVelocity(cap: 1500)), pet: id)
    }
}
