import AppKit
import CryptoKit

struct UpdateInfo {
    let version: AppVersion
    let downloadUrl: URL
    let size: Int
    let sha256: String?
}

/// Checks GitHub for a newer release (shortly after start, then daily) and installs it on request:
/// downloads Pastebird-mac-<version>.zip, verifies size and SHA-256 from GitHub, swaps the app bundle
/// once Pastebird has quit, and starts the new version. The zip is downloaded through pastebird.app/update.php,
/// which counts the update (only the old and the new version number) and forwards to GitHub. Nothing else about the
/// user is sent.
final class UpdateService {
    private static let firstCheckDelay: TimeInterval = 60
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 5 * 60
        // "Pastebird/<version>" is what pastebird.app/update.php counts; "(Mac)" tells the two apps apart.
        config.httpAdditionalHeaders = ["User-Agent": "Pastebird/\(AppInfo.version) (Mac)"]
        return URLSession(configuration: config)
    }()
    private var timer: Timer?
    private var installing = false

    /// Only from a real app bundle; `swift run` has nothing to replace.
    static var isSupported: Bool { AppInfo.isAppBundle }

    /// The newer version that was found, if any.
    private(set) var available: UpdateInfo?

    /// Called on the main thread when a newer version is found for the first time.
    var updateFound: ((UpdateInfo) -> Void)?

    var enabled: Bool {
        get { timer != nil }
        set {
            guard newValue != enabled, Self.isSupported else { return }
            timer?.invalidate()
            timer = nil
            if newValue { schedule(after: Self.firstCheckDelay) }
        }
    }

    private func schedule(after interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                _ = await self.check()
                if self.timer != nil { self.schedule(after: Self.checkInterval) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Asks GitHub for the latest release and updates `available`. Returns false when GitHub couldn't be reached.
    @MainActor
    func check() async -> Bool {
        guard Self.isSupported, let url = URL(string: AppInfo.latestReleaseApiUrl) else { return false }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            if let update = Self.parse(json), update.version > AppVersion.current, update.version != available?.version {
                available = update
                updateFound?(update)
            }
            return true
        } catch {
            // Offline or GitHub unreachable: try again at the next interval.
            return false
        }
    }

    private static func parse(_ release: [String: Any]) -> UpdateInfo? {
        if release["draft"] as? Bool == true || release["prerelease"] as? Bool == true { return nil }
        guard let version = AppVersion(release["tag_name"] as? String),
              let assets = release["assets"] as? [[String: Any]] else { return nil }

        for asset in assets {
            let name = asset["name"] as? String ?? ""
            guard name.hasPrefix("Pastebird-mac-"), name.hasSuffix(".zip") else { continue }
            guard let link = asset["browser_download_url"] as? String,
                  link.hasPrefix(AppInfo.gitHubUrl + "/releases/download/"),
                  let url = URL(string: link),
                  let size = asset["size"] as? Int else { return nil }

            // GitHub publishes "sha256:<hex>" for release assets.
            let digest = asset["digest"] as? String
            let sha256 = digest?.hasPrefix("sha256:") == true ? String(digest!.dropFirst("sha256:".count)) : nil
            return UpdateInfo(version: version, downloadUrl: url, size: size, sha256: sha256)
        }
        return nil
    }

    /// Downloads and verifies the update, then starts a small script that replaces Pastebird.app as soon as this
    /// process has quit and opens the new version. Returns true when the caller must quit now.
    @MainActor
    func downloadAndInstall(_ update: UpdateInfo) async -> Bool {
        guard !installing else { return false }
        installing = true
        defer { installing = false }
        do {
            let appURL = Bundle.main.bundleURL
            let parent = appURL.deletingLastPathComponent()
            guard FileManager.default.isWritableFile(atPath: parent.path) else {
                LocalStorage.log("Can't update: \(parent.path) is not writable.")
                return false
            }

            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Pastebird-update-\(update.version)", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            // First through pastebird.app, which counts the update (only the two version numbers) and forwards to the
            // same zip on GitHub; only when GitHub published its SHA-256, so the file is always checked against GitHub,
            // whatever the website sends. If that fails, straight from GitHub.
            var sources: [URL] = []
            if update.sha256 != nil,
               let counted = URL(string: "\(AppInfo.updateDownloadUrl)?to=\(update.version)&from=\(AppVersion.current)&os=mac") {
                sources.append(counted)
            }
            sources.append(update.downloadUrl)

            let zip = folder.appendingPathComponent("Pastebird.zip")
            var verified = false
            for source in sources where !verified {
                do {
                    let (downloaded, _) = try await session.download(from: source)
                    try? FileManager.default.removeItem(at: zip)
                    try FileManager.default.moveItem(at: downloaded, to: zip)
                } catch {
                    LocalStorage.log(error)
                    continue
                }
                let bytes = try Data(contentsOf: zip, options: .mappedIfSafe)
                let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                verified = bytes.count == update.size && (update.sha256 == nil || hash == update.sha256!.lowercased())
                if !verified { LocalStorage.log("Downloaded update \(update.version) from \(source) failed verification.") }
            }
            guard verified else { return false }

            let unpacked = folder.appendingPathComponent("unpacked", isDirectory: true)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            let newApp = unpacked.appendingPathComponent("Pastebird.app")
            guard let info = Bundle(url: newApp)?.infoDictionary,
                  info["CFBundleIdentifier"] as? String == AppInfo.bundleIdentifier,
                  AppVersion(info["CFBundleShortVersionString"] as? String) == update.version else {
                LocalStorage.log("The update \(update.version) doesn't contain the expected Pastebird.app.")
                return false
            }

            // Waits for Pastebird to quit, swaps the bundles (restoring the old one if that fails) and starts it.
            let script = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            rm -rf "$2.old"
            if mv "$2" "$2.old" && mv "$3" "$2"; then rm -rf "$2.old"; else mv "$2.old" "$2"; fi
            xattr -dr com.apple.quarantine "$2" 2>/dev/null
            open "$2"
            rm -rf "$4"
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier),
                                 appURL.path, newApp.path, folder.path]
            try process.run()
            return true
        } catch {
            LocalStorage.log(error)
            return false
        }
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Pastebird", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) failed"])
        }
    }
}
