import AppKit
import PokeToyCore

/// The catch game's on-screen parts: overlays that capture the mouse, the HUD, hit effects and results windows.
@MainActor
final class GameController {
    enum Status: Equatable {
        case idle
        case loading
        case running
        case failed(String)
        /// The round is over; the final score shows for a moment before the results.
        case finalScore(Int)
    }

    struct Effect {
        enum Kind { case flash, stars }
        let kind: Kind
        let position: CGPoint
        let start: CFTimeInterval
    }

    static let effectLength: CFTimeInterval = 0.6

    private unowned let model: AppModel
    private(set) var status: Status = .idle
    private(set) var effects: [Effect] = []
    private var overlays: [GameOverlayWindow] = []
    private var openResults: [ResultsWindowController] = []
    private var closeObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil,
                                                               queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                self?.openResults.removeAll { $0.window === (note.object as? NSWindow) }
            }
        }
    }

    /// Pokémon caught in rounds whose results window is still open; their sprites must stay loaded.
    var pendingCatchPaths: Set<String> {
        Set(openResults.flatMap(\.catchPaths))
    }

    func beginLoading() {
        status = .loading
        showOverlays()
    }

    func begin() {
        status = .running
    }

    /// Shows `message` in the HUD for three seconds, then closes the overlays.
    func fail(_ message: String) {
        status = .failed(message)
        redraw()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .failed = self.status else { return }
                self.finish()
            }
        }
    }

    /// Shows the final score for a moment, then closes the overlays and calls `then`.
    func showFinalScore(_ score: Int, then: @escaping () -> Void) {
        status = .finalScore(score)
        redraw()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .finalScore = self.status else { return }
                self.finish()
                then()
            }
        }
    }

    func finish() {
        status = .idle
        effects = []
        for overlay in overlays { overlay.close() }
        overlays = []
    }

    func addEffect(_ kind: Effect.Kind, at position: CGPoint) {
        effects.append(Effect(kind: kind, position: position, start: CACurrentMediaTime()))
    }

    /// Repaints only the parts of the overlays that change (balls, effects, HUD).
    func redraw() {
        let now = CACurrentMediaTime()
        effects.removeAll { now - $0.start > Self.effectLength }
        for overlay in overlays { overlay.gameView.refresh() }
    }

    func showResults(_ results: CatchResults, best: Int, isNewBest: Bool, keepable: Int, daily: Bool) {
        let controller = ResultsWindowController(model: model, results: results, best: best, isNewBest: isNewBest,
                                                 keepable: keepable, daily: daily)
        openResults.append(controller)
        controller.show()
    }

    private func showOverlays() {
        for overlay in overlays { overlay.close() }
        let primary = NSScreen.screens.first
        overlays = NSScreen.screens.map {
            GameOverlayWindow(screen: $0, showsHUD: $0 == primary, model: model, controller: self)
        }
        NSApp.activate()
        for overlay in overlays { overlay.orderFrontRegardless() }
        if let first = overlays.first {
            first.makeKeyAndOrderFront(nil)
            first.makeFirstResponder(first.gameView)
        }
    }
}
