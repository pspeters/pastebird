import Foundation

struct ChangelogSection {
    let type: String
    let items: [String]
}

struct ChangelogRelease {
    let version: AppVersion
    let date: String
    let sections: [ChangelogSection]
}

/// The repository's CHANGELOG.md, copied into the app by build.sh, so "What's new" works offline.
/// Understands "## [1.2.0] - date", "### Added" and "- item" lines; everything else is ignored.
enum Changelog {
    static func load() -> [ChangelogRelease] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Releases newer than `previous` up to and including `current`, newest first.
    static func between(_ previous: AppVersion?, _ current: AppVersion) -> [ChangelogRelease] {
        load().filter { $0.version <= current && (previous == nil || $0.version > previous!) }
    }

    static func parse(_ markdown: String) -> [ChangelogRelease] {
        let text = markdown.replacingOccurrences(of: "<!--.*?-->", with: "", options: .regularExpression)
        let release = try! NSRegularExpression(pattern: #"^## \[(\d+\.\d+\.\d+)\](?:\s*-\s*(\S+))?"#)

        var releases: [(version: AppVersion, date: String, sections: [(type: String, items: [String])])] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let range = NSRange(line.startIndex..., in: line)
            if let match = release.firstMatch(in: line, range: range),
               let versionRange = Range(match.range(at: 1), in: line),
               let version = AppVersion(String(line[versionRange])) {
                let date = Range(match.range(at: 2), in: line).map { String(line[$0]) } ?? ""
                releases.append((version, date, []))
            } else if !releases.isEmpty && line.hasPrefix("### ") {
                releases[releases.count - 1].sections.append((String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces), []))
            } else if !releases.isEmpty && (line.hasPrefix("- ") || line.hasPrefix("* ")) {
                if releases[releases.count - 1].sections.isEmpty { releases[releases.count - 1].sections.append(("", [])) }
                let s = releases[releases.count - 1].sections.count - 1
                releases[releases.count - 1].sections[s].items.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
        }
        return releases.map { r in
            ChangelogRelease(version: r.version, date: r.date,
                             sections: r.sections.filter { !$0.items.isEmpty }.map { ChangelogSection(type: $0.type, items: $0.items) })
        }
    }

    /// Splits "Press **Ctrl+P** to `pin`" into (text, bold) runs; links become their text.
    static func inlineRuns(_ item: String) -> [(text: String, bold: Bool)] {
        let plain = item
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "`", with: "")
        return plain.components(separatedBy: "**").enumerated()
            .filter { !$0.element.isEmpty }
            .map { ($0.element, $0.offset % 2 == 1) }
    }
}
