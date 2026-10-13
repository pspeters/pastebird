import Foundation

/// Product information shown in Settings → About.
enum AppInfo {
    static let gitHubUrl = "https://github.com/pspeters/pastebird"
    static let donateUrl = "https://ko-fi.com/pastebirdapp"
    static let releasesUrl = gitHubUrl + "/releases/latest"
    static let changelogUrl = "https://pastebird.app/changelog.php"
    static let latestReleaseApiUrl = "https://api.github.com/repos/pspeters/pastebird/releases/latest"

    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.pastebird.Pastebird"

    /// Set by build.sh from <Version> in the Windows project, so both platforms share one version number.
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    /// True when running from Pastebird.app (not from `swift run` during development).
    static let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
}

/// A "1.2.3" version number. Missing parts count as 0, so "1.2" equals "1.2.0".
struct AppVersion: Comparable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int

    init?(_ text: String?) {
        guard let text else { return nil }
        let parts = text.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".")
        guard (2...4).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers.count > 2 ? numbers[2] : 0
    }

    static let current = AppVersion(AppInfo.version) ?? AppVersion("0.0.0")!

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}
