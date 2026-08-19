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

    init(settings: AppSettings) {
        self.settings = settings
        try? fm.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
    }

    /// Pinned first, then by copy time.
    var ordered: [ClipItem] {
        items.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.copiedAt > b.copiedAt
        }
    }

    // MARK: - Mutations

    func add(kind: ClipKind, text: String, imageData: Data?, appName: String?, appBundleID: String?) {
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

        items.append(item)
        Log.write("store: added kind=\(kind.rawValue) length=\(text.count) total=\(items.count)")
        trim()
        scheduleSave()
    }

    func delete(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        removeImageFile(of: items[idx])
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
        items[idx].pinned.toggle()
        scheduleSave()
    }

    func clear(keepPinned: Bool) {
        let removed = items.filter { keepPinned ? !$0.pinned : true }
        removed.forEach(removeImageFile)
        items = keepPinned ? items.filter { $0.pinned } : []
        scheduleSave()
    }

    func image(for item: ClipItem) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        return NSImage(contentsOf: imagesURL.appendingPathComponent(file))
    }

    // MARK: - Pasteboard

    /// Puts an item on the system pasteboard. Returns true on success.
    @discardableResult
    func copyToPasteboard(_ item: ClipItem) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
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
        doomed.forEach(removeImageFile)
        items.removeAll { doomedIDs.contains($0.id) }
        unpinned.removeAll()
    }

    private func removeImageFile(of item: ClipItem) {
        guard let file = item.imageFile else { return }
        try? fm.removeItem(at: imagesURL.appendingPathComponent(file))
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
    }
}
