import Combine
import Foundation

/// A UI language: its code (the file name, e.g. "nl" or "pt-BR") and its name in that language.
struct UiLanguage: Hashable {
    let code: String
    let name: String
}

/// UI strings, shared with the Windows version: one JSON file per language in src/Pastebird/Languages, copied into
/// the app by build.sh (see docs/TRANSLATING.md). Where the Mac text differs, it is in the same key with ".mac"
/// added. SwiftUI views observe `Loc.shared`, so switching language updates open windows immediately. Code uses
/// `Loc.t(_:)`. Placeholders are written as {0}, {1} (and {0:N0} for a number). Missing strings fall back to English.
final class Loc: ObservableObject {
    private static let fallbackCode = "en"
    private static let packs = loadPacks()
    private static let english = packs[fallbackCode] ?? [:]

    static let shared = Loc()

    /// All languages Pastebird can show, sorted by name.
    static let languages: [UiLanguage] = packs
        .map { UiLanguage(code: $0.key, name: $0.value["language.name"] ?? $0.key) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    /// Code of the language in use.
    @Published private(set) var code = Loc.fallbackCode
    private var strings = Loc.english

    /// Locale for dates in the UI: the system's when it matches the UI language, otherwise a default for that language.
    private(set) var locale = Locale.current

    subscript(key: String) -> String {
        // A Mac text exists where the Windows one doesn't fit; then that one is used, also in English.
        let mac = key + ".mac"
        if let text = strings[mac] ?? Self.english[mac] { return text }
        return strings[key] ?? Self.english[key] ?? key
    }

    static func t(_ key: String) -> String { shared[key] }

    static func t(_ key: String, _ args: Any...) -> String {
        var text = shared[key]
        for (i, arg) in args.enumerated() {
            var number = "\(arg)"
            if let value = arg as? Int {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.locale = shared.locale
                number = formatter.string(from: NSNumber(value: value)) ?? number
            }
            text = text.replacingOccurrences(of: "{\(i):N0}", with: number)
                .replacingOccurrences(of: "{\(i)}", with: "\(arg)")
        }
        return text
    }

    /// Switches to the language with this code; nil (or a language that isn't there) follows macOS.
    func apply(_ language: String?) {
        let code = Self.resolve(language)
        strings = Self.packs[code] ?? Self.english
        let wanted = Locale(identifier: code).language.languageCode?.identifier
        locale = Locale.current.language.languageCode?.identifier == wanted ? Locale.current : Locale(identifier: code)
        self.code = code // notifies SwiftUI
    }

    private static func resolve(_ language: String?) -> String {
        if let language, let code = find(language) { return code }
        // The preferred macOS languages in order: exactly ("pt-BR") or just the language ("nl-BE" → "nl").
        for preferred in Locale.preferredLanguages {
            let parts = preferred.split(separator: "-").map(String.init)
            for candidate in [preferred, parts.prefix(2).joined(separator: "-"), parts.first ?? ""] {
                if let code = find(candidate) { return code }
            }
        }
        return fallbackCode
    }

    private static func find(_ code: String) -> String? {
        packs.keys.first { $0.caseInsensitiveCompare(code) == .orderedSame }
    }

    /// The languages built into Pastebird, plus files in ~/Library/Application Support/Pastebird/Languages, so a
    /// translator can try a translation without building Pastebird. Such a file adds to or overrides a built-in language.
    private static func loadPacks() -> [String: [String: String]] {
        var folders: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Languages", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.path) {
            folders.append(bundled)
        } else {
            // Not in an app bundle (swift run, the screenshot workflow): the files in the repository.
            folders.append(URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().appendingPathComponent("../../../../src/Pastebird/Languages", isDirectory: true)
                .standardizedFileURL)
        }
        folders.append(LocalStorage.folder.appendingPathComponent("Languages", isDirectory: true))

        var packs: [String: [String: String]] = [:]
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension.lowercased() == "json" {
                guard let data = try? Data(contentsOf: file),
                      let strings = (try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed])) as? [String: String]
                else { continue }
                let name = file.deletingPathExtension().lastPathComponent
                let code = packs.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
                packs[code, default: [:]].merge(strings) { _, new in new }
            }
        }
        if packs[fallbackCode] == nil { packs[fallbackCode] = [:] }
        return packs
    }
}
