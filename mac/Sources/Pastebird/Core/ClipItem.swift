import Foundation

enum ClipKind: String, Codable {
    case text, url, filePath, files, image
}

/// One entry in the clipboard history.
final class ClipItem: Codable {
    var id = UUID()

    /// The text, URL, path or file list (one path per line). For images: the SHA-256 of the PNG, to recognize the same image again.
    var content = ""
    var copiedAt = Date.distantPast
    var lastUsedAt: Date?

    /// Pinned items stay at the top, don't count towards the history size and survive "Clear history".
    var isPinned = false

    /// True when the formatting of copied text (HTML/RTF) is stored next to it, see `ClipData`.
    var hasFormatting = false

    var imageWidth = 0
    var imageHeight = 0

    /// Small PNG shown in the popup for images; the full image is in `ClipData`.
    var thumbnail: Data?

    /// Text recognized in an image ("" when it has none); nil until the recognition has run.
    var imageText: String? { didSet { _searchText = nil } }

    var kind = ClipKind.text { didSet { _preview = nil } }

    private var _preview: String?
    private var _searchText: [Unicode.Scalar]?

    private enum CodingKeys: String, CodingKey {
        case id, content, copiedAt, lastUsedAt, isPinned, hasFormatting, imageWidth, imageHeight, thumbnail, imageText, kind
    }

    init(content: String, kind: ClipKind, hasFormatting: Bool = false) {
        self.content = content
        self.kind = kind
        self.hasFormatting = hasFormatting
    }

    init(imageHash: String, width: Int, height: Int, thumbnail: Data?) {
        content = imageHash
        kind = .image
        imageWidth = width
        imageHeight = height
        self.thumbnail = thumbnail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        copiedAt = try c.decodeIfPresent(Date.self, forKey: .copiedAt) ?? .distantPast
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        hasFormatting = try c.decodeIfPresent(Bool.self, forKey: .hasFormatting) ?? false
        imageWidth = try c.decodeIfPresent(Int.self, forKey: .imageWidth) ?? 0
        imageHeight = try c.decodeIfPresent(Int.self, forKey: .imageHeight) ?? 0
        thumbnail = try c.decodeIfPresent(Data.self, forKey: .thumbnail)
        imageText = try c.decodeIfPresent(String.self, forKey: .imageText)
        kind = (try? c.decodeIfPresent(ClipKind.self, forKey: .kind)) ?? .text
    }

    /// True when the item has a `ClipData` file next to the history.
    var hasData: Bool { hasFormatting || kind == .image }

    /// The paths of a file list.
    var files: [String] { content.split(separator: "\n").map(String.init) }

    /// Single-line text shown in the popup.
    var preview: String {
        if kind == .files || kind == .image { return buildPreview() } // these contain translated text
        if let p = _preview { return p }
        let p = buildPreview()
        _preview = p
        return p
    }

    /// SF Symbol for the item type.
    var symbolName: String {
        switch kind {
        case .url: return "link"
        case .filePath: return "doc"
        case .files: return "folder"
        case .image: return "photo"
        case .text: return "text.alignleft"
        }
    }

    /// Lower-cased (and capped) content used by the search; for images the label and the recognized text.
    var searchText: [Unicode.Scalar] {
        if let s = _searchText { return s }
        let text = kind == .image
            ? Self.capped(Loc.t("item.image", imageWidth, imageHeight) + "\n" + (imageText ?? "")).lowercased()
            : Self.capped(content).lowercased()
        let s = Array(text.unicodeScalars)
        _searchText = s
        return s
    }

    /// Drops the cached texts after a language change.
    func resetCachedTexts() {
        _searchText = nil
        _preview = nil
    }

    private static func capped(_ text: String) -> String { text.count > 10_000 ? String(text.prefix(10_000)) : text }

    private func buildPreview() -> String {
        if kind == .image {
            // The start of the recognized text helps to tell screenshots apart.
            let label = Loc.t("item.image", imageWidth, imageHeight)
            let text = Self.collapseWhitespace(String((imageText ?? "").prefix(200)))
            return text.isEmpty ? label : "\(label) · \(text)"
        }
        if kind == .files {
            let files = self.files
            if files.count > 1 {
                return Loc.t("item.files", files.count) + files.prefix(6).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            }
        }
        return Self.collapseWhitespace(String(content.prefix(400)))
    }

    /// Collapses all whitespace (newlines, tabs) so multi-line text fits on one row.
    private static func collapseWhitespace(_ source: String) -> String {
        var result = ""
        result.reserveCapacity(source.count)
        var space = false
        for c in source {
            if c.isWhitespace { space = !result.isEmpty; continue }
            if space { result.append(" "); space = false }
            result.append(c)
        }
        return result
    }

    /// Decides whether copied text is a URL, a file path or plain text.
    static func detectKind(_ text: String) -> ClipKind {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if t.isEmpty || t.count > 2048 || t.contains("\n") { return .text }
        if looksLikePath(t) { return .filePath }
        if t.contains(" ") { return .text }
        if let url = URL(string: t), let scheme = url.scheme?.lowercased(),
           ["http", "https", "ftp", "mailto"].contains(scheme), url.host != nil || scheme == "mailto" {
            return .url
        }
        if t.lowercased().hasPrefix("www."), let dot = t.dropFirst(4).firstIndex(of: "."), dot > t.index(t.startIndex, offsetBy: 4) {
            return .url
        }
        return .text
    }

    /// "/Users/…", "~/…" and Windows paths (copied from a shared document, say).
    private static func looksLikePath(_ t: String) -> Bool {
        let chars = Array(t.prefix(3))
        if t.hasPrefix("~/") || (t.hasPrefix("/") && t.count > 1 && !t.hasPrefix("//")) {
            return t.dropFirst().contains("/") || FileManager.default.fileExists(atPath: t)
        }
        if chars.count == 3, chars[0].isASCII, chars[0].isLetter, chars[1] == ":", chars[2] == "\\" || chars[2] == "/" { return true }
        return t.count > 3 && t.hasPrefix(#"\\"#)
    }
}
