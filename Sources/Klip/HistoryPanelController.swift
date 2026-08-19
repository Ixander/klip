import AppKit
import SwiftUI

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let model: HistoryPanelModel
    private let store: HistoryStore
    private let settings: AppSettings
    private let monitor: ClipboardMonitor

    private var panel: NSPanel?
    private var keyMonitor: Any?
    /// Held strongly: NSWorkspace hands back an unretained object, so a weak ref would clear at once.
    private var previousApp: NSRunningApplication?

    var onOpenSettings: (() -> Void)?

    init(store: HistoryStore, settings: AppSettings, monitor: ClipboardMonitor) {
        self.store = store
        self.settings = settings
        self.monitor = monitor
        self.model = HistoryPanelModel(store: store, settings: settings)
        super.init()
        model.onConfirm = { [weak self] item in self?.confirm(item) }
        model.onClose = { [weak self] in self?.hide(restoreFocus: true) }
        model.onOpenSettings = { [weak self] in
            self?.hide(restoreFocus: false)
            self?.onOpenSettings?()
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide(restoreFocus: true) } else { show() }
    }

    func show() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = front
        }
        Log.write("panel: show, items in store=\(store.items.count)")
        model.reset()

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKey()
        }
        Log.write("panel: visible=\(panel.isVisible) rows shown=\(model.visible.count)")

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.panel?.isKeyWindow == true else { return event }
                let consumed = MainActor.assumeIsolated { self.model.handle(event) }
                return consumed ? nil : event
            }
        }
    }

    func hide(restoreFocus: Bool) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
        if restoreFocus, let previousApp, previousApp.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp.activate()
        }
    }

    // MARK: - Private

    private func confirm(_ item: ClipItem) {
        activate(item, restoreFocusTo: previousApp)
    }

    /// Copies the item, returns focus to the target app and (optionally) sends ⌘V.
    func activate(_ item: ClipItem, restoreFocusTo target: NSRunningApplication?) {
        guard store.copyToPasteboard(item) else {
            Log.write("activate: could not write to the pasteboard")
            return
        }
        monitor.acknowledgeOwnChange()
        store.markUsed(item)

        if isVisible { hide(restoreFocus: false) }
        if let target, target.processIdentifier != NSRunningApplication.current.processIdentifier {
            target.activate()
        }
        Log.write("activate: kind=\(item.kind.rawValue) target=\(target?.localizedName ?? "—") autoPaste=\(settings.pasteAutomatically) trusted=\(Paster.isTrusted)")

        guard settings.pasteAutomatically else { return }
        guard Paster.isTrusted else {
            Paster.requestAccess()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.sendPaste()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KlipPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HistoryView(model: model, store: store))
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + frame.height * 0.12
        )
        panel.setFrameOrigin(origin)
    }

    // Close the panel once it loses focus.
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        hide(restoreFocus: false)
    }
}

/// A titleless panel must opt in to becoming the key window.
private final class KlipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
