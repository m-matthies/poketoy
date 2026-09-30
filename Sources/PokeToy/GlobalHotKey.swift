import AppKit
import Carbon.HIToolbox
import PokeToyCore

/// A system-wide keyboard shortcut (Carbon hot key). Works in any app without extra permissions;
/// the key combination is taken by PokeToy, so pick one other apps don't use.
@MainActor
final class GlobalHotKey {
    private static var nextID: UInt32 = 1

    private let action: () -> Void
    private let id: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// False when macOS refused the combination (another app registered it first).
    var isRegistered: Bool { hotKey != nil }

    init(_ shortcut: Shortcut, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressedID)
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            // Every hot key's handler sees every press: only the one it belongs to acts.
            guard pressedID.signature == GlobalHotKey.signature, pressedID.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let hotKeyID = EventHotKeyID(signature: GlobalHotKey.signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0,
                                         &hotKey)
        if status != noErr { hotKey = nil }
    }

    /// Gives the combination back to macOS (before registering it again).
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    private nonisolated static let signature = OSType(0x504B_5459)  // 'PKTY'

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
