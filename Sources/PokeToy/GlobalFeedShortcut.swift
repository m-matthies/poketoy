import AppKit
import ApplicationServices

/// Listens for ⌘B in other apps and feeds the pets. The key is only observed, never consumed,
/// so the frontmost app still receives it. (While PokeToy is frontmost, the Feed menu item handles ⌘B.)
///
/// Watching other apps' keys needs Accessibility permission: the first start asks for it, and the
/// shortcut switches on by itself once it is granted in System Settings.
@MainActor
final class GlobalFeedShortcut {
    private let action: () -> Void
    private var monitor: Any?
    private var waitForPermission: Timer?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            install()
            return
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.waitForPermission?.invalidate()
                self.waitForPermission = nil
                self.install()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        waitForPermission = timer
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "b" else { return }
            MainActor.assumeIsolated { self?.action() }
        }
    }
}
