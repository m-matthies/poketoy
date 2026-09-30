import AppKit
import PokeToyCore

/// Full-screen, nearly transparent window that takes the mouse during a catch round and draws the balls and HUD.
@MainActor
final class GameOverlayWindow: NSWindow {
    let gameView: GameView

    init(screen: NSScreen, showsHUD: Bool, model: AppModel, controller: GameController) {
        gameView = GameView(model: model, controller: controller, showsHUD: showsHUD)
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.06)  // a faint tint shows the game has the mouse
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        contentView = gameView
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class GameView: NSView {
    private unowned let model: AppModel
    private unowned let controller: GameController
    private let showsHUD: Bool
    private var drag = DragTracker()
    private var holding = false
    private var lastDirty: [NSRect] = []

    init(model: AppModel, controller: GameController, showsHUD: Bool) {
        self.model = model
        self.controller = controller
        self.showsHUD = showsHUD
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var ballSize: CGFloat { CGFloat(ItemArt.size) * model.playground.scale }

    /// The clickable "End" button in the HUD's corner (a way out even when Esc doesn't reach us).
    private var endButtonRect: NSRect {
        NSRect(x: bounds.maxX - 110, y: bounds.maxY - 84, width: 90, height: 32)
    }

    private var showsEndButton: Bool {
        showsHUD && (controller.status == .loading || controller.status == .running)
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if showsEndButton, endButtonRect.contains(local) {
            model.endCatchGame()
            return
        }
        holding = true
        let point = NSEvent.mouseLocation
        drag.begin(at: point, objectPosition: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard holding else { return }
        _ = drag.move(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard holding else { return }
        holding = false
        let point = NSEvent.mouseLocation
        model.throwBall(from: CGPoint(x: point.x, y: point.y - ballSize / 2), velocity: drag.releaseVelocity(cap: 2200))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            model.endCatchGame()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    /// Marks what changed since the last frame as needing display, instead of the whole screen.
    func refresh() {
        let current = dirtyRects()
        for rect in lastDirty + current { setNeedsDisplay(rect) }
        lastDirty = current
    }

    private func dirtyRects() -> [NSRect] {
        guard let window else { return [] }
        let origin = window.frame.origin
        let size = ballSize
        var rects = model.playground.items.filter { $0.kind == .pokeBall }.map { item in
            NSRect(x: item.body.position.x - origin.x - size, y: item.body.position.y - origin.y - size / 2,
                   width: size * 2, height: size * 2)
        }
        if holding {
            let mouse = NSEvent.mouseLocation
            rects.append(NSRect(x: mouse.x - origin.x - size, y: mouse.y - origin.y - size, width: size * 2, height: size * 2))
        }
        rects += controller.effects.map { effectRect($0, origin: origin) }
        if showsHUD {
            if let hud = hudLayout() { rects.append(hud.background.insetBy(dx: -2, dy: -2)) }
            rects.append(endButtonRect.insetBy(dx: -2, dy: -2))
        }
        return rects.map { $0.intersection(bounds) }.filter { !$0.isEmpty }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let window, let context = NSGraphicsContext.current?.cgContext else { return }
        let origin = window.frame.origin
        let size = ballSize
        let ball = ItemArt.frame(for: .pokeBall).image
        context.interpolationQuality = .none
        for item in model.playground.items where item.kind == .pokeBall {
            let base = CGPoint(x: item.body.position.x - origin.x, y: item.body.position.y - origin.y)
            guard bounds.insetBy(dx: -size, dy: -size).contains(base) else { continue }
            context.saveGState()
            context.translateBy(x: base.x, y: base.y + size / 2)
            context.rotate(by: -item.wobbleAngle)
            if case .fading(let remaining) = item.state { context.setAlpha(CGFloat(min(1, max(0, remaining / 0.5)))) }
            context.draw(ball, in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
            context.restoreGState()
        }
        if holding {
            let mouse = NSEvent.mouseLocation
            context.draw(ball, in: CGRect(x: mouse.x - origin.x - size / 2, y: mouse.y - origin.y - size / 2,
                                          width: size, height: size))
        }
        drawEffects(origin: origin)
        if showsHUD { drawHUD() }
    }

    private func effectRect(_ effect: GameController.Effect, origin: CGPoint) -> NSRect {
        let center = CGPoint(x: effect.position.x - origin.x, y: effect.position.y - origin.y + 20)
        return NSRect(x: center.x - 64, y: center.y - 64, width: 128, height: 128)
    }

    private func drawEffects(origin: CGPoint) {
        let now = CACurrentMediaTime()
        for effect in controller.effects {
            let t = CGFloat(min(1, (now - effect.start) / GameController.effectLength))
            let center = CGPoint(x: effect.position.x - origin.x, y: effect.position.y - origin.y + 20)
            switch effect.kind {
            case .flash:  // the Pokémon is pulled into the ball
                let radius = 10 + 40 * t
                NSColor.systemRed.withAlphaComponent(0.6 * (1 - t)).setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2)).fill()
            case .stars:  // caught!
                let star = NSAttributedString(string: "✦", attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 22),
                    .foregroundColor: NSColor.systemYellow.withAlphaComponent(1 - t),
                ])
                for k in 0..<5 {
                    let angle = CGFloat(k) / 5 * 2 * .pi
                    let distance = 12 + 36 * t
                    star.draw(at: CGPoint(x: center.x + cos(angle) * distance - 8, y: center.y + sin(angle) * distance - 10))
                }
            }
        }
    }

    private func hudLayout() -> (text: NSAttributedString, origin: CGPoint, background: NSRect)? {
        var big = false
        let text: String
        switch controller.status {
        case .idle:
            return nil
        case .loading:
            text = "Getting wild Pokémon…"
        case .failed(let message):
            text = message
        case .finalScore(let score):
            text = "Time!  ★ \(score)"
            big = true
        case .running:
            guard let game = model.playground.game else { return nil }
            switch game.phase {
            case .countdown(let remaining):
                text = "\(max(1, Int(remaining.rounded(.up))))"
                big = true
            case .playing(let remaining) where remaining > CatchGame.roundLength - 0.8:
                text = "Go!"
                big = true
            case .playing(let remaining):
                text = "⏱ \(Int(remaining.rounded(.up)))    ★ \(game.score)    ◓ \(game.catches.count)    Click & flick to throw"
            case .finished:
                return nil
            }
        }
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: big ? 96 : 20, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
        let size = string.size()
        let origin = CGPoint(x: (bounds.width - size.width) / 2,
                             y: big ? (bounds.height - size.height) / 2 : bounds.height - size.height - 48)
        let background = NSRect(x: origin.x - 16, y: origin.y - 8, width: size.width + 32, height: size.height + 16)
        return (string, origin, background)
    }

    private func drawHUD() {
        if let hud = hudLayout() {
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: hud.background, xRadius: 12, yRadius: 12).fill()
            hud.text.draw(at: hud.origin)
        }
        guard showsEndButton else { return }
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: endButtonRect, xRadius: 8, yRadius: 8).fill()
        let label = NSAttributedString(string: "End ✕", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        let size = label.size()
        label.draw(at: CGPoint(x: endButtonRect.midX - size.width / 2, y: endButtonRect.midY - size.height / 2))
    }
}
