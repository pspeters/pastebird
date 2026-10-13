import CryptoKit
import Foundation
import Security

/// Stores everything under ~/Library/Application Support/Pastebird (per user, readable only by that user).
/// The history and the per-item data are additionally encrypted (AES-GCM) with a key that lives in the user's
/// Keychain and never leaves this Mac, so copies of the files (in a backup, say) are unreadable.
final class LocalStorage {
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pastebird", isDirectory: true)
    }()

    private static var historyURL: URL { folder.appendingPathComponent("history.dat") }
    private static var dataFolder: URL { folder.appendingPathComponent("data", isDirectory: true) }
    private static var settingsURL: URL { folder.appendingPathComponent("settings.json") }

    /// Nil when the Keychain refused the key; the history then stays in memory only, so nothing is overwritten.
    private let key: SymmetricKey?

    init() {
        Self.createFolder(Self.folder)
        key = Self.loadOrCreateKey()
    }

    var settingsExist: Bool { FileManager.default.fileExists(atPath: Self.settingsURL.path) }

    func loadHistory() -> [ClipItem] {
        do {
            guard FileManager.default.fileExists(atPath: Self.historyURL.path) else { return [] }
            guard let key else { return [] }
            let json = try Self.decrypt(Data(contentsOf: Self.historyURL), key)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ClipItem].self, from: json)
        } catch {
            Self.log(error)
            return []
        }
    }

    /// Saves the history and removes the `ClipData` files of items that are no longer in it,
    /// except those of `removedButUndoable`.
    func saveHistory(_ items: [ClipItem], removedButUndoable: [ClipItem]) {
        guard let key else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try Self.encrypt(encoder.encode(items), key).write(to: Self.historyURL, options: .atomic)
            removeUnusedData(items + removedButUndoable)
        } catch {
            Self.log(error)
        }
    }

    /// Stores the formatting or image of an item (encrypted like the history), or removes it when there is none.
    func saveData(_ item: ClipItem, _ data: ClipData?) {
        do {
            let url = dataURL(item.id)
            guard let data else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            guard let key else { return }
            Self.createFolder(Self.dataFolder)
            try Self.encrypt(data.serialize(), key).write(to: url, options: .atomic)
        } catch {
            Self.log(error)
        }
    }

    func loadData(_ item: ClipItem) -> ClipData? {
        guard item.hasData, let key else { return nil }
        do {
            let url = dataURL(item.id)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try ClipData.deserialize(Self.decrypt(Data(contentsOf: url), key))
        } catch {
            Self.log(error)
            return nil
        }
    }

    private func dataURL(_ id: UUID) -> URL {
        Self.dataFolder.appendingPathComponent(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased() + ".dat")
    }

    private func removeUnusedData(_ items: [ClipItem]) {
        let used = Set(items.filter(\.hasData).map { dataURL($0.id).lastPathComponent })
        guard let files = try? FileManager.default.contentsOfDirectory(at: Self.dataFolder, includingPropertiesForKeys: nil) else { return }
        for file in files where !used.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func loadSettings() -> AppSettings {
        do {
            if FileManager.default.fileExists(atPath: Self.settingsURL.path) {
                return try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: Self.settingsURL)).normalized()
            }
        } catch {
            Self.log(error)
        }
        return AppSettings()
    }

    func saveSettings(_ settings: AppSettings) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: Self.settingsURL, options: .atomic)
        } catch {
            Self.log(error)
        }
    }

    static func log(_ error: Error, file: String = #fileID, line: Int = #line) {
        log("\(error) (\(file):\(line))")
    }

    static func log(_ message: String) {
        let url = folder.appendingPathComponent("error.log")
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 256 * 1024 {
            try? FileManager.default.removeItem(at: url)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let entry = Data("[\(formatter.string(from: Date()))] \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(entry)
            try? handle.close()
        } else {
            try? entry.write(to: url) // logging must never take the app down
        }
    }

    // ---------------------------------------------------------------- encryption

    private static func encrypt(_ plain: Data, _ key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw CocoaError(.coderInvalidValue) }
        return combined
    }

    private static func decrypt(_ sealed: Data, _ key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }

    private static let keychainService = "Pastebird"
    private static let keychainAccount = "History encryption key"

    private static func loadOrCreateKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            log("Keychain refused the history key (\(status)); the history is not saved this session.")
            return nil
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrLabel as String: "Pastebird",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: keyData,
        ]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else {
            log("Couldn't store the history key in the Keychain (\(added)).")
            return nil
        }
        // A new key can't read files written with an earlier one.
        try? FileManager.default.removeItem(at: historyURL)
        try? FileManager.default.removeItem(at: dataFolder)
        return key
    }

    private static func createFolder(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}
