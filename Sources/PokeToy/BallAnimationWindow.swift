import AppKit
import PokeToyCore

/// Plays a Poké Ball animation (returning a pet, or letting one out) in a transparent panel over the pet's spot.
@MainActor
final class BallAnimationWindow: NSPanel {
    private let animationView: BallAnimationView
    private var timer: Timer?
    private var started: CFTimeInterval = 0
    private let kind: BallAnimation.Kind
    private var completion: (() -> Void)?

    /// `spriteRect` is where the pet's sprite is on screen; `ballCenter` where the ball rests.
    init(kind: BallAnimation.Kind, sprite: CGImage, spriteRect: NSRect, ballCenter: CGPoint, ballSize: CGFloat) {
        self.kind = kind
        let ballRect = NSRect(x: ballCenter.x - ballSize, y: ballCenter.y - ballSize,
                              width: ballSize * 2, height: ballSize * 2 + 140)  // room for the drop and the burst
        let area = spriteRect.union(ballRect).insetBy(dx: -ballSize * 2, dy: -ballSize * 2).integral
        animationView = BallAnimationView(kind: kind, sprite: sprite,
                                          spriteRect: spriteRect.offsetBy(dx: -area.minX, dy: -area.minY),
                                          ballCenter: CGPoint(x: ballCenter.x - area.minX, y: ballCenter.y - area.minY),
                                          ballSize: ballSize)
        super.init(contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        CapturePolicy.apply(to: self)  // out of screen sharing when the player wants
        contentView = animationView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func play(then completion: @escaping () -> Void) {
        self.completion = completion
        started = CACurrentMediaTime()
        animationView.time = 0
        orderFrontRegardless()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        let t = CACurrentMediaTime() - started
        animationView.time = t
        animationView.needsDisplay = true
        guard t >= BallAnimation.duration(kind) else { return }
        timer?.invalidate()
        timer = nil
        orderOut(nil)
        let done = completion
        completion = nil
        done?()
    }
}

@MainActor
private final class BallAnimationView: NSView {
    var time: Double = 0
    private let kind: BallAnimation.Kind
    private let sprite: CGImage
    private let spriteRect: CGRect
    private let ballCenter: CGPoint
    private let ballSize: CGFloat
    private static let ball = ItemArt.frame(for: .pokeBall).image

    init(kind: BallAnimation.Kind, sprite: CGImage, spriteRect: CGRect, ballCenter: CGPoint, ballSize: CGFloat) {
        self.kind = kind
        self.sprite = sprite
        self.spriteRect = spriteRect
        self.ballCenter = ballCenter
        self.ballSize = ballSize
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        context.interpolationQuality = .none
        let f = BallAnimation.frame(kind, at: time)

        // The pet: shrinking into (or growing out of) the ball, tinted red or glowing white.
        if f.petScale > 0.01 {
            let size = CGSize(width: spriteRect.width * f.petScale, height: spriteRect.height * f.petScale)
            let home = CGPoint(x: spriteRect.midX, y: spriteRect.minY)  // grows from, shrinks to, its feet
            let base = CGPoint(x: home.x + (ballCenter.x - home.x) * f.toBall,
                               y: home.y + (ballCenter.y - size.height / 2 - home.y) * f.toBall)
            let rect = CGRect(x: base.x - size.width / 2, y: base.y, width: size.width, height: size.height)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.draw(sprite, in: rect)
            if f.tint > 0 {
                context.setBlendMode(.sourceAtop)  // only over the sprite's own pixels
                let color = f.tintIsRed ? NSColor.systemRed : NSColor.white
                context.setFillColor(color.withAlphaComponent(f.tint * 0.85).cgColor)
                context.fill(rect)
                context.setBlendMode(.normal)
            }
            context.endTransparencyLayer()
        }

        // The white burst of the ball opening.
        if f.burst > 0 {
            let radius = ballSize * (0.4 + 2.2 * f.burst)
            context.setFillColor(NSColor.white.withAlphaComponent(0.85 * (1 - f.burst)).cgColor)
            context.fillEllipse(in: CGRect(x: ballCenter.x - radius, y: ballCenter.y - radius,
                                           width: radius * 2, height: radius * 2))
        }

        // The ball: popping up, falling in, wobbling, fading.
        guard f.ballAlpha > 0, f.ballScale > 0 else { return }
        context.saveGState()
        context.setAlpha(f.ballAlpha)
        context.translateBy(x: ballCenter.x, y: ballCenter.y - ballSize / 2 + f.ballDrop)  // pivot at its bottom
        context.rotate(by: -f.ballAngle)
        let side = ballSize * f.ballScale
        context.draw(Self.ball, in: CGRect(x: -side / 2, y: 0, width: side, height: side))
        context.restoreGState()
    }
}
