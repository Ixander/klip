import AppKit
import Carbon.HIToolbox

/// Global hot key via Carbon RegisterEventHotKey — works without Accessibility.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var callback: (() -> Void)?
    private let hotKeyID: UInt32 = 1

    private init() {}

    func setHandler(_ handler: @escaping () -> Void) {
        callback = handler
        installHandlerIfNeeded()
    }

    /// Re-registers the hot key. Returns false if the combination is taken.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4B4C4950 /* KLIP */), id: hotKeyID)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            Log.write("hotkey: REGISTRATION FAILED code=\(keyCode) mods=\(modifiers) OSStatus=\(status)")
            return false
        }
        hotKeyRef = ref
        Log.write("hotkey: registered code=\(keyCode) mods=\(modifiers)")
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    fileprivate func fire(_ id: UInt32) {
        Log.write("hotkey: fired id=\(id)")
        guard id == hotKeyID else { return }
        callback?()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), klipHotKeyHandler, 1, &spec, nil, &handlerRef)
        Log.write("hotkey: InstallEventHandler OSStatus=\(status)")
    }
}

private func klipHotKeyHandler(_ nextHandler: EventHandlerCallRef?,
                               _ event: EventRef?,
                               _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hkID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hkID)
    guard status == noErr else { return status }
    let id = hkID.id
    DispatchQueue.main.async { HotKeyCenter.shared.fire(id) }
    return noErr
}
