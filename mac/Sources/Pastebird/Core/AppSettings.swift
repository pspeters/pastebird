import Foundation

/// The few user settings Pastebird has. Defaults are chosen so nobody needs to open Settings.
struct AppSettings: Codable {
    static let historySizes = [50, 100, 200, 500]

    /// Choices for `keepDays`; 0 keeps items until the history is full.
    static let keepDayChoices = [0, 1, 7, 30]

    var startAtLogin = true
    var pasteAutomatically = true
    var checkForUpdates = true

    /// Version that ran last time; a lower value means Pastebird was just updated.
    var lastRunVersion: String?
    var maxItems = 200

    /// Unpinned items older than this many days are removed; 0 never removes them by age.
    var keepDays = 0
    var language = AppLanguage.system
    var hotkeyModifiers = Hotkey.default.modifiers
    var hotkeyKey = Hotkey.default.keyCode

    var hotkey: Hotkey {
        get { Hotkey(modifiers: hotkeyModifiers, keyCode: hotkeyKey) }
        set { hotkeyModifiers = newValue.modifiers; hotkeyKey = newValue.keyCode }
    }

    init() {}

    // Settings written by an older version may miss keys; those keep their default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? d.startAtLogin
        pasteAutomatically = try c.decodeIfPresent(Bool.self, forKey: .pasteAutomatically) ?? d.pasteAutomatically
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? d.checkForUpdates
        lastRunVersion = try c.decodeIfPresent(String.self, forKey: .lastRunVersion)
        maxItems = try c.decodeIfPresent(Int.self, forKey: .maxItems) ?? d.maxItems
        keepDays = try c.decodeIfPresent(Int.self, forKey: .keepDays) ?? d.keepDays
        language = (try? c.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? d.language
        hotkeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? d.hotkeyModifiers
        hotkeyKey = try c.decodeIfPresent(UInt32.self, forKey: .hotkeyKey) ?? d.hotkeyKey
    }

    func normalized() -> AppSettings {
        var s = self
        if !Self.historySizes.contains(s.maxItems) { s.maxItems = 200 }
        if !Self.keepDayChoices.contains(s.keepDays) { s.keepDays = 0 }
        if !s.hotkey.isValid { s.hotkey = .default }
        return s
    }
}
