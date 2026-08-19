import AppKit
import CryptoKit

enum ClipKind: String, Codable {
    case text
    case image
    case fileURL
}

struct ClipItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ClipKind
    /// Text, file paths (one per line), or "" for an image.
    var text: String
    /// File name inside images/ when kind == .image
    var imageFile: String?
    var pinned: Bool = false
    var copiedAt: Date = Date()
    var appName: String?
    var appBundleID: String?
    /// Deduplication key.
    var digest: String

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(of string: String) -> String {
        digest(of: Data(string.utf8))
    }

    /// Single-line preview text for the list.
    var preview: String {
        switch kind {
        case .image:
            return "Image"
        case .fileURL:
            let paths = text.split(separator: "\n").map { ($0 as NSString).lastPathComponent }
            return paths.joined(separator: ", ")
        case .text:
            let collapsed = text
                .replacingOccurrences(of: "\n", with: " ⏎ ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return collapsed.isEmpty ? "(empty)" : collapsed
        }
    }

    var symbolName: String {
        switch kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .fileURL: return "doc"
        }
    }
}
