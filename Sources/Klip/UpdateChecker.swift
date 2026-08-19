import AppKit

/// Asks GitHub Releases whether a newer version exists.
///
/// Deliberately minimal: it never downloads or replaces anything, it only
/// surfaces a menu item linking to the release page. That keeps the app free
/// of the code-signing requirements a real self-updater would carry.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release {
        let version: String
        let url: URL
    }

    /// Repository to ask about.
    static let repository = "Ixander/klip"
    /// How rarely to ask. This is a courtesy check, not telemetry.
    private static let interval: TimeInterval = 48 * 60 * 60
    /// How often to wake up and see whether `interval` has elapsed.
    private static let tick: TimeInterval = 60 * 60

    @Published private(set) var available: Release?

    /// Called on the main actor when a newer version appears.
    var onUpdateFound: (() -> Void)?

    private let settings: AppSettings
    private let defaults = UserDefaults.standard
    private let lastCheckKey = "lastUpdateCheck"
    private var timer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func start() {
        checkIfDue()
        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Ignores the schedule — used by the "Check now" button in Settings.
    func checkNow() {
        fetch()
    }

    // MARK: - Private

    private func checkIfDue() {
        guard settings.checkForUpdates else { return }
        let last = defaults.object(forKey: lastCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < Self.interval { return }
        fetch()
    }

    private func fetch() {
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Klip/\(currentVersion) (+https://github.com/\(Self.repository))",
                         forHTTPHeaderField: "User-Agent")

        defaults.set(Date(), forKey: lastCheckKey)

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error {
                Log.write("update: request failed: \(error.localizedDescription)")
                return
            }
            // 404 simply means the repository has no published release yet.
            guard status == 200, let data else {
                Log.write("update: HTTP \(status)")
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = json["html_url"] as? String,
                  let pageURL = URL(string: page) else {
                Log.write("update: unexpected response shape")
                return
            }
            let isDraft = json["draft"] as? Bool ?? false
            let isPrerelease = json["prerelease"] as? Bool ?? false
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.apply(tag: tag, url: pageURL, skip: isDraft || isPrerelease)
                }
            }
        }.resume()
    }

    private func apply(tag: String, url: URL, skip: Bool) {
        let latest = Self.normalized(tag)
        guard !skip, Self.isNewer(tag, than: currentVersion) else {
            Log.write("update: latest=\(latest) current=\(currentVersion) — up to date")
            available = nil
            return
        }
        Log.write("update: latest=\(latest) current=\(currentVersion) — newer version available")
        available = Release(version: latest, url: url)
        onUpdateFound?()
    }

    // MARK: - Version comparison

    /// Drops a leading "v" so "v0.2.0" and "0.2.0" compare equal.
    static func normalized(_ version: String) -> String {
        var s = version.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        return s
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate)
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        normalized(version)
            .split(separator: ".")
            .map { part in Int(String(part.prefix { $0.isNumber })) ?? 0 }
    }
}
