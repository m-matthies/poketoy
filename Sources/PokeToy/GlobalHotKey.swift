import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut (Carbon hot key). Works in any app without extra permissions;
/// the key combination is taken by PokeToy, so pick one other apps don't use.
@MainActor
final class GlobalHotKey {
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// `keyCode` is a virtual key code (e.g. `kVK_ANSI_B`), `modifiers` Carbon flags (e.g. `controlKey | optionKey`).
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: OSType(0x504B_5459), id: 1)  // 'PKTY'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
