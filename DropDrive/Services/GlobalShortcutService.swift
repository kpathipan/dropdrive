import Carbon.HIToolbox
import Foundation

/// A dependency-free global shortcut for the app's one primary surface.
/// Control-Option-D is intentionally different from macOS's Command-Option-D
/// (Show/Hide Dock) and common browser bookmark shortcuts.
@MainActor
final class GlobalShortcutService {
    static let displayName = "⌃⌥D"
    private static let signature: OSType = 0x4444484B // "DDHK"
    private static let identifier: UInt32 = 1

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: @MainActor () -> Void

    init?(action: @escaping @MainActor () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == GlobalShortcutService.signature,
                      hotKeyID.id == GlobalShortcutService.identifier else {
                    return OSStatus(eventNotHandledErr)
                }

                let service = Unmanaged<GlobalShortcutService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated { service.action() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
        guard handlerStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registrationStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
