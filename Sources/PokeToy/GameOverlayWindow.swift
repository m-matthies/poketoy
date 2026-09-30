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

    override func mouseDown(with event: NSEvent) {
        holding = true
        let point = NSEvent.mouseLocation
        drag.begin(at: point, objectPosition: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        _ = drag.move(to: NSEvent.mouseLocation)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard holding else { return }
        holding = false
        let point = NSEvent.mouseLocation
        let ballHeight = CGFloat(ItemArt.size) * model.playground.scale
        model.throwBall(from: CGPoint(x: point.x, y: point.y - ballHeight / 2), velocity: drag.releaseVelocity(cap: 2200))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            model.endCatchGame()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let window, let context = NSGraphicsContext.current?.cgContext else { return }
        let origin = window.frame.origin
        let size = CGFloat(ItemArt.size) * model.playground.scale
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
        if showsHUD { drawHUD() }
    }

    private func drawHUD() {
        var big = false
        let text: String
        switch controller.status {
        case .idle:
            return
        case .loading:
            text = "Getting wild Pokémon…"
        case .failed(let message):
            text = message
        case .running:
            guard let game = model.playground.game else { return }
            switch game.phase {
            case .countdown(let remaining):
                text = "\(max(1, Int(remaining.rounded(.up))))"
                big = true
            case .playing(let remaining) where remaining > CatchGame.roundLength - 0.8:
                text = "Go!"
                big = true
            case .playing(let remaining):
                text = "⏱ \(Int(remaining.rounded(.up)))    ★ \(game.score)    ◓ \(game.catches.count)    Esc to stop"
            case .finished:
                return
            }
        }
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: big ? 96 : 20, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
        let size = string.size()
        let x = (bounds.width - size.width) / 2
        let y = big ? (bounds.height - size.height) / 2 : bounds.height - size.height - 48
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 16, y: y - 8, width: size.width + 32, height: size.height + 16),
                     xRadius: 12, yRadius: 12).fill()
        string.draw(at: CGPoint(x: x, y: y))
    }
}
