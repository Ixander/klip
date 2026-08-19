import SwiftUI
import Carbon.HIToolbox

/// A field that records the key combination you press.
struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        view.onRecord = { code, mods in
            keyCode = code
            modifiers = mods
        }
        return view
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.display(KeyNames.description(keyCode: keyCode, carbonModifiers: modifiers))
    }

    final class RecorderButton: NSButton {
        var onRecord: ((UInt32, UInt32) -> Void)?
        private var recording = false
        private var monitor: Any?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(toggleRecording)
        }

        required init?(coder: NSCoder) { fatalError() }

        func display(_ text: String) {
            guard !recording else { return }
            title = text
        }

        @objc private func toggleRecording() {
            recording.toggle()
            if recording {
                title = "Press a combination…"
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                    guard let self, event.type == .keyDown else { return event }
                    let mods = KeyNames.carbonModifiers(from: event.modifierFlags)
                    if Int(event.keyCode) == kVK_Escape {
                        self.stop()
                        return nil
                    }
                    guard mods != 0 else { return nil }
                    self.onRecord?(UInt32(event.keyCode), mods)
                    self.stop()
                    return nil
                }
            } else {
                stop()
            }
        }

        private func stop() {
            recording = false
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
