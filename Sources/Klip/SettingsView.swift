import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: HistoryStore
    @ObservedObject var updates: UpdateChecker
    var onHotKeyChange: () -> Void

    @State private var accessibilityGranted = Paster.isTrusted

    var body: some View {
        Form {
            Section {
                LabeledContent("Hot key") {
                    HotKeyRecorderView(
                        keyCode: Binding(get: { settings.hotKeyCode }, set: { settings.hotKeyCode = $0; onHotKeyChange() }),
                        modifiers: Binding(get: { settings.hotKeyModifiers }, set: { settings.hotKeyModifiers = $0; onHotKeyChange() })
                    )
                    .frame(width: 190, height: 24)
                }

                Stepper(value: $settings.maxItems, in: 10...2000, step: 10) {
                    LabeledContent("History size", value: "\(settings.maxItems)")
                }

                Toggle("Paste automatically (⌘V)", isOn: $settings.pasteAutomatically)
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }

            Section("Updates") {
                Toggle("Check GitHub for new versions", isOn: $settings.checkForUpdates)
                HStack {
                    if let update = updates.available {
                        Text("Version \(update.version) is available.")
                            .font(.callout)
                        Spacer()
                        Button("Open release page") { NSWorkspace.shared.open(update.url) }
                    } else {
                        Text("Version \(updates.currentVersion) — the latest one known.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Check now") { updates.checkNow() }
                    }
                }
            }

            Section("Access") {
                HStack {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Text(accessibilityGranted
                         ? "Accessibility granted — auto-paste works."
                         : "Without Accessibility items are only copied to the clipboard.")
                        .font(.callout)
                    Spacer()
                    if !accessibilityGranted {
                        Button("Open Settings") { Paster.openAccessibilitySettings() }
                    }
                }
            }

            Section {
                HStack {
                    Text("Items in history: \(store.items.count)")
                    Spacer()
                    Button("Clear (keep pinned)") { store.clear(keepPinned: true) }
                    Button("Clear all") { store.clear(keepPinned: false) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 400)
        .onAppear { accessibilityGranted = Paster.isTrusted }
    }
}
