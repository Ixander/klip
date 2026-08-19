import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var settings: AppSettings!
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var panel: HistoryPanelController!
    private var updates: UpdateChecker!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var hotKeyFailed = false
    /// Held strongly: NSWorkspace hands back an unretained object, so a weak ref would clear at once.
    private var menuTargetApp: NSRunningApplication?
    /// How many history items to show directly in the status bar menu.
    private let menuHistoryLimit = 12

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = AppSettings()
        store = HistoryStore(settings: settings)
        monitor = ClipboardMonitor(settings: settings)
        panel = HistoryPanelController(store: store, settings: settings, monitor: monitor)
        panel.onOpenSettings = { [weak self] in self?.openSettings() }

        monitor.onCopy = { [weak self] snapshot, app in
            self?.store.add(
                kind: snapshot.kind,
                text: snapshot.text,
                imageData: snapshot.imageData,
                richText: snapshot.richText,
                appName: app?.localizedName,
                appBundleID: app?.bundleIdentifier
            )
        }
        monitor.start()

        HotKeyCenter.shared.setHandler { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggle() }
        }
        registerHotKey()

        setupStatusItem()

        updates = UpdateChecker(settings: settings)
        updates.onUpdateFound = { [weak self] in self?.rebuildMenu() }
        updates.start()

        Log.write("app: launched, hotkey=\(settings.hotKeyDescription), history=\(store.items.count)")

        // For manual testing: KLIP_SHOW_ON_LAUNCH=1 open -a Klip
        if ProcessInfo.processInfo.environment["KLIP_SHOW_ON_LAUNCH"] == "1" {
            panel.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
        monitor.stop()
        updates.stop()
        HotKeyCenter.shared.unregister()
    }

    // MARK: - Status bar menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Klip")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Remember where to paste while the menu has not taken focus yet.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != NSRunningApplication.current.processIdentifier {
            menuTargetApp = front
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        if let update = updates?.available {
            let item = NSMenuItem(title: "Update available → \(update.version)",
                                  action: #selector(openReleasePage), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let all = store.ordered
        let pinned = all.filter(\.pinned)
        let recent = Array(all.filter { !$0.pinned }.prefix(menuHistoryLimit))

        if pinned.isEmpty && recent.isEmpty {
            let empty = NSMenuItem(title: "History is empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        // Pinned block: each entry keeps its own letter, so it stays put.
        for item in pinned {
            let menuItem = historyMenuItem(for: item, keyEquivalent: item.pinKey ?? "")
            menuItem.state = .on
            menu.addItem(menuItem)
        }
        if !pinned.isEmpty && !recent.isEmpty { menu.addItem(.separator()) }

        for (index, item) in recent.enumerated() {
            menu.addItem(historyMenuItem(for: item,
                                         keyEquivalent: index < 9 ? String(index + 1) : ""))
        }

        menu.addItem(.separator())

        let search = NSMenuItem(title: "Search history…  (\(settings.hotKeyDescription))",
                                action: #selector(showPanel), keyEquivalent: "")
        search.target = self
        menu.addItem(search)

        let clear = NSMenuItem(title: "Clear (keep pinned)", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Klip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func historyMenuItem(for item: ClipItem, keyEquivalent: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: menuTitle(for: item),
                                  action: #selector(historyItemPicked(_:)),
                                  keyEquivalent: keyEquivalent)
        menuItem.keyEquivalentModifierMask = .command
        menuItem.target = self
        menuItem.representedObject = item.id
        menuItem.image = menuIcon(for: item)
        return menuItem
    }

    private func menuTitle(for item: ClipItem) -> String {
        let preview = item.preview
        let limit = 60
        guard preview.count > limit else { return preview }
        return String(preview.prefix(limit)) + "…"
    }

    private func menuIcon(for item: ClipItem) -> NSImage? {
        if item.kind == .image, let thumb = store.image(for: item) {
            let size = NSSize(width: 20, height: 14)
            let scaled = NSImage(size: size)
            scaled.lockFocus()
            thumb.draw(in: NSRect(origin: .zero, size: size))
            scaled.unlockFocus()
            return scaled
        }
        let image = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func historyItemPicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = store.items.first(where: { $0.id == id }) else { return }
        // Modifiers only mean something for a click: a ⌘1 accelerator holds ⌘
        // by construction, so reading it would make every shortcut copy-only.
        let byClick = NSApp.currentEvent.map { $0.type != .keyDown } ?? false
        let modifiers = byClick ? NSEvent.modifierFlags : []
        panel.activate(item, restoreFocusTo: menuTargetApp, modifiers: modifiers)
    }

    func registerHotKey() {
        let ok = HotKeyCenter.shared.register(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
        if !ok {
            hotKeyFailed = true
            let alert = NSAlert()
            alert.messageText = "Hot key already taken"
            alert.informativeText = "\(settings.hotKeyDescription) is already used by another app. Pick a different one in Settings."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { openSettings() }
        } else {
            hotKeyFailed = false
        }
        if statusItem != nil { rebuildMenu() }
    }

    @objc func showPanel() {
        panel.show()
    }

    @objc private func clearHistory() {
        store.clear(keepPinned: true)
    }

    @objc private func openReleasePage() {
        guard let url = updates?.available?.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openSettings() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(settings: settings, store: store, updates: updates) { [weak self] in
            self?.registerHotKey()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Klip Settings"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
