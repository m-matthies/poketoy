import AppKit

/// A small speech-bubble panel above a pet showing its emotion portrait (or an emoji).
@MainActor
final class BubbleWindow: NSPanel {
    private let bubbleView = BubbleView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 56, height: 62),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = bubbleView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(image: NSImage?, emoji: String) {
        bubbleView.image = image
        bubbleView.emoji = emoji
        bubbleView.needsDisplay = true
    }

    /// Puts the bubble's tail at `point` (just above the pet), kept inside `bounds` when given.
    func place(tailAt point: CGPoint, within bounds: CGRect?) {
        var origin = NSPoint(x: (point.x - frame.width / 2).rounded(), y: point.y.rounded())
        if let bounds {
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - frame.width)
            origin.y = min(origin.y, bounds.maxY - frame.height)
        }
        if frame.origin != origin { setFrameOrigin(origin) }
        if !isVisible { orderFrontRegardless() }
    }
}

@MainActor
final class BubbleView: NSView {
    var image: NSImage?
    var emoji = ""

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 2, y: 8, width: bounds.width - 4, height: bounds.height - 10)
        let path = NSBezierPath(roundedRect: body, xRadius: 12, yRadius: 12)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bounds.midX - 6, y: body.minY + 1))
        tail.line(to: NSPoint(x: bounds.midX, y: 1))
        tail.line(to: NSPoint(x: bounds.midX + 6, y: body.minY + 1))
        tail.close()
        NSColor.white.setFill()
        path.fill()
        tail.fill()
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()

        let content = body.insetBy(dx: 4, dy: 4)
        if let image {
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: content)
        } else {
            let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 28)])
            let size = text.size()
            text.draw(at: NSPoint(x: content.midX - size.width / 2, y: content.midY - size.height / 2))
        }
    }
}

/// A small pill above a pet with its Pomodoro countdown ("🍅 24:59").
@MainActor
final class BadgeWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let pill = NSView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 72, height: 20),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 9
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        contentView = pill
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ text: String) {
        guard label.stringValue != text else { return }
        label.stringValue = text
        let width = ceil(label.intrinsicContentSize.width) + 14
        if abs(frame.width - width) > 0.5 { setContentSize(NSSize(width: width, height: 18)) }
    }

    /// Centers the pill horizontally on `x` with its bottom at `y`, kept inside `bounds` when given.
    func place(centerX x: CGFloat, bottom y: CGFloat, within bounds: CGRect?) {
        var origin = NSPoint(x: (x - frame.width / 2).rounded(), y: y.rounded())
        if let bounds {
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - frame.width)
            origin.y = min(origin.y, bounds.maxY - frame.height)
        }
        if frame.origin != origin { setFrameOrigin(origin) }
        if !isVisible { orderFrontRegardless() }
    }
}

/// A small text field that pops up right above a pet to name its task. Return saves, Esc cancels, clicking
/// elsewhere saves. It takes typing without pulling the user's app out of focus.
@MainActor
final class TaskEditorPanel: NSPanel, NSTextFieldDelegate {
    private let field = NSTextField()
    private var onDone: ((String?) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 36),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        field.placeholderString = "What are you working on?"
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    /// Shows the editor centered above `anchor` (the pet's frame) with `text`; `done` gets the new text, or nil
    /// when cancelled.
    func edit(text: String, above anchor: CGRect, within bounds: CGRect?, done: @escaping (String?) -> Void) {
        finish(with: nil)  // a previous edit still open is dropped
        onDone = done
        field.stringValue = text
        var origin = NSPoint(x: anchor.midX - frame.width / 2, y: anchor.maxY + 4)
        if let bounds {
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - frame.width)
            origin.y = min(origin.y, bounds.maxY - frame.height)
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            finish(with: field.stringValue)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finish(with: nil)
            return true
        default:
            return false
        }
    }

    override func resignKey() {
        super.resignKey()
        if onDone != nil { finish(with: field.stringValue) }  // clicked elsewhere: keep what was typed
    }

    private func finish(with text: String?) {
        guard let done = onDone else { return }
        onDone = nil
        orderOut(nil)
        done(text)
    }
}
