import AppKit
import PokeToyCore

@MainActor
protocol PetViewDelegate: AnyObject {
    func petViewPressed()
    func petViewClicked()
    func petViewDragBegan(at point: CGPoint)
    func petViewDragMoved(to point: CGPoint)
    func petViewDragEnded()
}

/// Borderless transparent panel that floats above every app, on every Space, sized to the current sprite frame.
@MainActor
final class PetWindow: NSPanel {
    static let heartSpace: CGFloat = 24

    let petView = PetView()
    private var sprite: SpriteFrame?
    private var spriteScale: CGFloat = 2

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        contentView = petView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Positions the panel so the sprite's feet sit at `feet` and draws `sprite` with `hearts` above it.
    func render(sprite: SpriteFrame, footPadding: Int, hearts: Int, feet: CGPoint, scale: CGFloat, flash: CGFloat = 0) {
        let width = CGFloat(sprite.image.width) * scale
        let height = CGFloat(sprite.image.height) * scale
        let rect = NSRect(x: (feet.x - width / 2).rounded(), y: (feet.y - CGFloat(footPadding) * scale).rounded(),
                          width: width, height: height + Self.heartSpace)
        if rect != frame { setFrame(rect, display: false) }
        if petView.frameImage !== sprite.image || petView.hearts != hearts || petView.flash != flash {
            petView.frameImage = sprite.image
            petView.hearts = hearts
            petView.flash = flash
            petView.needsDisplay = true
        }
        self.sprite = sprite
        spriteScale = scale
    }

    /// True if `screenPoint` is on (or within one pixel of) an opaque sprite pixel.
    func hitsSprite(at screenPoint: CGPoint) -> Bool {
        guard let sprite, isVisible else { return false }
        let x = Int(floor((screenPoint.x - frame.minX) / spriteScale))
        let yFromBottom = Int(floor((screenPoint.y - frame.minY) / spriteScale))
        let y = sprite.mask.height - 1 - yFromBottom
        for dx in -1...1 {
            for dy in -1...1 where sprite.mask.isOpaque(x: x + dx, y: y + dy) { return true }
        }
        return false
    }
}

@MainActor
final class PetView: NSView {
    weak var delegate: PetViewDelegate?
    var frameImage: CGImage?
    var hearts = 0
    /// 0…1: how strongly the sprite glows white (evolving).
    var flash: CGFloat = 0
    private var mouseDownPoint: CGPoint?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = frameImage, let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        context.interpolationQuality = .none
        let spriteRect = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - PetWindow.heartSpace)
        context.draw(image, in: spriteRect)
        if flash > 0 {
            // Tint only the sprite's own pixels.
            context.saveGState()
            context.setBlendMode(.sourceAtop)
            context.setFillColor(NSColor.white.withAlphaComponent(flash).cgColor)
            context.fill(spriteRect)
            context.restoreGState()
        }
        if hearts > 0 {
            let text = NSAttributedString(string: String(repeating: "♥", count: hearts), attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.systemPink,
            ])
            let size = text.size()
            text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: spriteRect.maxY - 4))
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = NSEvent.mouseLocation
        dragging = false
        delegate?.petViewPressed()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = NSEvent.mouseLocation
        if !dragging, hypot(point.x - start.x, point.y - start.y) > 3 {
            dragging = true
            delegate?.petViewDragBegan(at: start)
        }
        if dragging { delegate?.petViewDragMoved(to: point) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            delegate?.petViewDragEnded()
        } else if mouseDownPoint != nil {
            delegate?.petViewClicked()
        }
        mouseDownPoint = nil
        dragging = false
    }
}
