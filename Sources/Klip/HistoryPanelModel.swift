import AppKit
import Combine
import Carbon.HIToolbox

@MainActor
final class HistoryPanelModel: ObservableObject {
    @Published var query: String = "" { didSet { refresh(resetSelection: true) } }
    @Published private(set) var visible: [ClipItem] = []
    /// Shortcut hint per row: ⌘<letter> for pinned entries, ⌘1…⌘9 for the rest.
    @Published private(set) var shortcuts: [UUID: String] = [:]
    @Published var selectedID: UUID?

    let store: HistoryStore
    let settings: AppSettings

    var onConfirm: ((ClipItem) -> Void)?
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    init(store: HistoryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(resetSelection: false) }
            .store(in: &cancellables)
        refresh(resetSelection: true)
    }

    func reset() {
        query = ""
        refresh(resetSelection: true)
    }

    func refresh(resetSelection: Bool) {
        let all = store.ordered
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        if needle.isEmpty {
            visible = all
        } else {
            visible = all
                .compactMap { item -> (ClipItem, Int)? in
                    guard let score = Self.score(item.searchText.lowercased(), needle) else { return nil }
                    return (item, item.pinned ? score + 500 : score)
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        rebuildShortcuts()
        if resetSelection || selectedID == nil || !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
    }

    private func rebuildShortcuts() {
        var map: [UUID: String] = [:]
        var rank = 0
        for item in visible {
            if item.pinned {
                if let key = item.pinKey { map[item.id] = "⌘" + key.uppercased() }
            } else {
                if rank < 9 { map[item.id] = "⌘\(rank + 1)" }
                rank += 1
            }
        }
        shortcuts = map
    }

    // MARK: - Keyboard

    /// true means the panel consumed the event.
    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let code = Int(event.keyCode)

        switch code {
        case kVK_Escape:
            onClose?()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            confirmSelection()
            return true
        case kVK_DownArrow:
            move(by: 1)
            return true
        case kVK_UpArrow:
            move(by: -1)
            return true
        case kVK_PageDown:
            move(by: 8)
            return true
        case kVK_PageUp:
            move(by: -8)
            return true
        default:
            break
        }

        // ⌥P toggles the pin, the way Maccy does it.
        if flags.contains(.option), code == kVK_ANSI_P {
            togglePinSelection()
            return true
        }

        guard cmd else { return false }

        switch code {
        case kVK_Delete, kVK_ForwardDelete:
            deleteSelection()
            return true
        case kVK_ANSI_P:
            togglePinSelection()
            return true
        case kVK_ANSI_Comma:
            onOpenSettings?()
            return true
        default:
            // ⌘1…⌘9 count unpinned entries only, so pins never shift them.
            if let digit = Self.digit(for: code) {
                let index = digit == 0 ? 9 : digit - 1
                let recent = visible.filter { !$0.pinned }
                if index < recent.count {
                    selectedID = recent[index].id
                    confirmSelection()
                }
                return true
            }
            // ⌘<letter> picks the pinned entry holding that letter.
            if let typed = event.charactersIgnoringModifiers?.lowercased(), typed.count == 1,
               let pin = visible.first(where: { $0.pinned && $0.pinKey == typed }) {
                selectedID = pin.id
                confirmSelection()
                return true
            }
            return false
        }
    }

    func confirmSelection() {
        guard let item = selectedItem else { return }
        onConfirm?(item)
    }

    func deleteSelection() {
        guard let item = selectedItem else { return }
        let idx = visible.firstIndex(where: { $0.id == item.id }) ?? 0
        store.delete(item)
        refresh(resetSelection: false)
        if !visible.isEmpty {
            selectedID = visible[min(idx, visible.count - 1)].id
        } else {
            selectedID = nil
        }
    }

    func togglePinSelection() {
        guard let item = selectedItem else { return }
        store.togglePin(item)
        refresh(resetSelection: false)
        selectedID = item.id
    }

    var selectedItem: ClipItem? {
        guard let selectedID else { return nil }
        return visible.first { $0.id == selectedID }
    }

    private func move(by delta: Int) {
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), visible.count - 1)
        selectedID = visible[next].id
    }

    private static func digit(for keyCode: Int) -> Int? {
        switch keyCode {
        case kVK_ANSI_1: return 1
        case kVK_ANSI_2: return 2
        case kVK_ANSI_3: return 3
        case kVK_ANSI_4: return 4
        case kVK_ANSI_5: return 5
        case kVK_ANSI_6: return 6
        case kVK_ANSI_7: return 7
        case kVK_ANSI_8: return 8
        case kVK_ANSI_9: return 9
        case kVK_ANSI_0: return 0
        default: return nil
        }
    }

    /// An exact match outranks a fuzzy one.
    static func score(_ haystack: String, _ needle: String) -> Int? {
        if let range = haystack.range(of: needle) {
            let offset = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            return 10_000 - min(offset, 9_000)
        }
        // Fuzzy: characters occurring in order.
        var idx = haystack.startIndex
        var gaps = 0
        for ch in needle {
            guard let found = haystack[idx...].firstIndex(of: ch) else { return nil }
            gaps += haystack.distance(from: idx, to: found)
            idx = haystack.index(after: found)
        }
        return max(1, 900 - gaps)
    }
}

extension ClipItem {
    var searchText: String {
        switch kind {
        case .text, .fileURL: return text
        case .image: return "image " + (appName ?? "")
        }
    }
}
