import AppKit

/// Keeps PokeToy's on-screen overlays (pets, bubbles, countdowns, treats, animations, the catch game) out of screen
/// sharing and screenshots when the player wants that: their windows are marked as not capturable.
@MainActor
enum CapturePolicy {
    /// Set from Preferences ("Keep pets out of screen sharing and screenshots").
    static var excluded = true {
        didSet {
            guard excluded != oldValue else { return }
            for window in NSApp.windows where window is CaptureExcludable { apply(to: window) }
        }
    }

    static func apply(to window: NSWindow) {
        window.sharingType = excluded ? .none : .readOnly
    }
}

/// An overlay window that follows `CapturePolicy`.
@MainActor
protocol CaptureExcludable: NSWindow {}

extension PetWindow: CaptureExcludable {}
extension BubbleWindow: CaptureExcludable {}
extension BadgeWindow: CaptureExcludable {}
extension TaskEditorPanel: CaptureExcludable {}
extension BallAnimationWindow: CaptureExcludable {}
extension GameOverlayWindow: CaptureExcludable {}
