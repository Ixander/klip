import AppKit

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let settings: AppSettings
    private let fm = FileManager.default
    private var saveWorkItem: DispatchWorkItem?

    private lazy var rootURL: URL = {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Klip", isDirectory: true)
    }()
    private var historyURL: URL { rootURL.appendingPathComponent("history.json") }
    private var imagesURL: URL { rootURL.appendingPathComponent("images", isDirectory: true) }
    private var richURL: URL { rootURL.appendingPathComponent("rich", isDirectory: true) }

    init(settings: AppSettings) {
        self.settings = settings
        try? fm.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: richURL, withIntermediateDirectories: true)
        load()
    }

    /// Letters handed out to pinned entries, in this order. "p" is left out
    /// because ⌘P toggles pinning, "q" because ⌘Q quits.
    static let pinKeys: [String] = Array("asdfghjkl;wertyuiozxcvbnm").map(String.init)

    /// Pinned first — ordered by their letter so they never move — then the
    /// rest by copy time.
    var ordered: [ClipItem] {
        let pinned = items.filter(\.pinned).sorted { Self.pinRank($0) < Self.pinRank($1) }
        let recent = items.filter { !$0.pinned }.sorted { $0.copiedAt > $1.copiedAt }
        return pinned + recent
    }

    private static func pinRank(_ item: ClipItem) -> Int {
        guard let key = item.pinKey, let idx = pinKeys.firstIndex(of: key) else { return .max }
        return idx
    }

    // MARK: - Mutations

    func add(kind: ClipKind, text: String, imageData: Data?, richText: Data?,
             appName: String?, appBundleID: String?) {
        let digest: String
        if let imageData {
            digest = ClipItem.digest(of: imageData)
        } else {
            digest = ClipItem.digest(of: kind.rawValue + "\u{1}" + text)
        }

        if let idx = items.firstIndex(where: { $0.digest == digest }) {
            // Duplicate — just move it to the top.
            items[idx].copiedAt = Date()
            items[idx].appName = appName ?? items[idx].appName
            items[idx].appBundleID = appBundleID ?? items[idx].appBundleID
            scheduleSave()
            return
        }

        var item = ClipItem(kind: kind, text: text, digest: digest)
        item.appName = appName
        item.appBundleID = appBundleID

        if let imageData {
            let name = item.id.uuidString + ".png"
            try? imageData.write(to: imagesURL.appendingPathComponent(name))
            item.imageFile = name
        }
        if let richText {
            let name = item.id.uuidString + ".rtf"
            try? richText.write(to: richURL.appendingPathComponent(name))
            item.richTextFile = name
        }

        items.append(item)
        Log.write("store: added kind=\(kind.rawValue) length=\(text.count) total=\(items.count)")
        trim()
        scheduleSave()
    }

    func delete(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        removeFiles(of: items[idx])
        items.remove(at: idx)
        scheduleSave()
    }

    /// Moves an item back to the top after it is reused.
    func markUsed(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].copiedAt = Date()
        scheduleSave()
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if items[idx].pinned {
            items[idx].pinned = false
            items[idx].pinKey = nil
        } else {
            items[idx].pinned = true
            items[idx].pinKey = firstFreePinKey()
        }
        scheduleSave()
    }

    /// Lowest unused letter, or nil once every letter is taken.
    private func firstFreePinKey() -> String? {
        let taken = Set(items.compactMap(\.pinKey))
        return Self.pinKeys.first { !taken.contains($0) }
    }

    func clear(keepPinned: Bool) {
        let removed = items.filter { keepPinned ? !$0.pinned : true }
        removed.forEach(removeFiles)
        items = keepPinned ? items.filter { $0.pinned } : []
        scheduleSave()
    }

    func image(for item: ClipItem) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        return NSImage(contentsOf: imagesURL.appendingPathComponent(file))
    }

    // MARK: - Pasteboard

    /// Puts an item on the system pasteboard. Returns true on success.
    ///
    /// `stripFormatting` drops the RTF flavour of a text entry, so the target
    /// app receives plain text and styles it itself.
    @discardableResult
    func copyToPasteboard(_ item: ClipItem, stripFormatting: Bool = false) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            if !stripFormatting, let file = item.richTextFile,
               let rtf = try? Data(contentsOf: richURL.appendingPathComponent(file)) {
                pb.declareTypes([.rtf, .string], owner: nil)
                pb.setData(rtf, forType: .rtf)
                return pb.setString(item.text, forType: .string)
            }
            pb.declareTypes([.string], owner: nil)
            return pb.setString(item.text, forType: .string)
        case .fileURL:
            let urls = item.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            guard !urls.isEmpty else { return false }
            let ok = pb.writeObjects(urls as [NSURL])
            pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            return ok
        case .image:
            guard let file = item.imageFile,
                  let data = try? Data(contentsOf: imagesURL.appendingPathComponent(file)) else { return false }
            return pb.setData(data, forType: .png)
        }
    }

    // MARK: - Private

    private func trim() {
        let limit = max(10, settings.maxItems)
        var unpinned = items.filter { !$0.pinned }.sorted { $0.copiedAt > $1.copiedAt }
        guard unpinned.count > limit else { return }
        let doomed = unpinned[limit...]
        let doomedIDs = Set(doomed.map(\.id))
        doomed.forEach(removeFiles)
        items.removeAll { doomedIDs.contains($0.id) }
        unpinned.removeAll()
    }

    private func removeFiles(of item: ClipItem) {
        if let file = item.imageFile {
            try? fm.removeItem(at: imagesURL.appendingPathComponent(file))
        }
        if let file = item.richTextFile {
            try? fm.removeItem(at: richURL.appendingPathComponent(file))
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            Log.write("store: save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([ClipItem].self, from: data)) ?? []
        // Drop images whose files are gone.
        items.removeAll { $0.kind == .image && !fm.fileExists(atPath: imagesURL.appendingPathComponent($0.imageFile ?? "-").path) }
        // Entries pinned before pin letters existed still need one. Persist the
        // assignment, otherwise it is redone (differently) on every launch.
        var migrated = false
        for idx in items.indices where items[idx].pinned && items[idx].pinKey == nil {
            items[idx].pinKey = firstFreePinKey()
            migrated = true
        }
        if migrated {
            Log.write("store: assigned pin letters to \(items.filter { $0.pinned }.count) pinned entries")
            scheduleSave()
        }
    }
}
