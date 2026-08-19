import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// What picking an entry should do. Two independent axes: whether the RTF
/// flavour is dropped on the way to the pasteboard, and whether ⌘V is sent
/// afterwards. Stripping happens during the copy, so it applies even when
/// nothing is pasted.
struct PasteBehavior: Equatable, CustomStringConvertible {
    var stripsFormatting: Bool
    var sendsPaste: Bool

    var description: String {
        (sendsPaste ? "paste" : "copyOnly") + (stripsFormatting ? "+plain" : "")
    }

    /// Held modifiers win over the configured default: ⌘ copies, ⌥ copies and
    /// pastes, ⌥⇧ copies, clears formatting and pastes.
    @MainActor
    static func resolve(modifiers: NSEvent.ModifierFlags, settings: AppSettings) -> PasteBehavior {
        let held = modifiers.intersection(.deviceIndependentFlagsMask)
        if held.contains(.option) && held.contains(.shift) {
            return PasteBehavior(stripsFormatting: true, sendsPaste: true)
        }
        if held.contains(.option) {
            return PasteBehavior(stripsFormatting: false, sendsPaste: true)
        }
        if held.contains(.command) {
            return PasteBehavior(stripsFormatting: settings.pasteWithoutFormatting, sendsPaste: false)
        }
        return PasteBehavior(stripsFormatting: settings.pasteWithoutFormatting,
                             sendsPaste: settings.pasteAutomatically)
    }
}

enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt asking for Accessibility.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Emulates ⌘V in the currently active app.
    static func sendPaste() {
        guard isTrusted else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
