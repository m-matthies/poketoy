import AppKit
import PokeToyCore

/// The catch game's on-screen parts: overlays that capture the mouse, the HUD and the results window.
@MainActor
final class GameController {
    enum Status: Equatable {
        case idle
        case loading
        case running
        case failed(String)
    }

    private unowned let model: AppModel
    private(set) var status: Status = .idle
    private var overlays: [GameOverlayWindow] = []
    private var results: ResultsWindowController?

    init(model: AppModel) {
        self.model = model
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

    func finish() {
        status = .idle
        for overlay in overlays { overlay.close() }
        overlays = []
    }

    func redraw() {
        for overlay in overlays { overlay.gameView.needsDisplay = true }
    }

    func showResults(_ results: CatchResults, best: Int, isNewBest: Bool, keepable: Int) {
        let controller = ResultsWindowController(model: model, results: results, best: best, isNewBest: isNewBest,
                                                 keepable: keepable)
        self.results = controller
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
            first.makeKey()
            first.makeFirstResponder(first.gameView)
        }
    }
}
