import Carbon.HIToolbox
import Foundation

/// Registers one system-wide shortcut with RegisterEventHotKey. Unlike a key-event tap, this needs no permission.
final class GlobalHotkeyService {
    private static let signature: OSType = 0x5042_5244 // "PBRD"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var pressed: (() -> Void)?

    var isRegistered: Bool { hotKeyRef != nil }

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == GlobalHotkeyService.signature, let userData else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { service.pressed?() }
            return noErr
        }, 1, &spec, me, &handlerRef)
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Replaces the current shortcut. Returns false if another app already owns it.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}
