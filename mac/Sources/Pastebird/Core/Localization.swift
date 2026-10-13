import Combine
import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case system, english, dutch
}

/// UI strings in English and Dutch. SwiftUI views observe `Loc.shared`, so switching language updates open
/// windows immediately. Code uses `Loc.t(_:)`. Placeholders are written as {0}, {1}, like in the Windows version.
final class Loc: ObservableObject {
    static let shared = Loc()

    @Published private(set) var language = AppLanguage.system
    private var strings = Loc.english

    /// True when the UI is in Dutch.
    private(set) var isDutch = false

    /// Locale for dates in the UI: the system's when it matches the UI language, otherwise a default for that language.
    private(set) var locale = Locale.current

    subscript(key: String) -> String { strings[key] ?? Self.english[key] ?? key }

    static func t(_ key: String) -> String { shared[key] }

    static func t(_ key: String, _ args: Any...) -> String {
        var text = shared[key]
        for (i, arg) in args.enumerated() {
            text = text.replacingOccurrences(of: "{\(i)}", with: "\(arg)")
        }
        return text
    }

    func apply(_ language: AppLanguage) {
        let systemLanguage = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        isDutch = language == .dutch || (language == .system && systemLanguage == "nl")
        strings = isDutch ? Self.dutch : Self.english
        let wanted = isDutch ? "nl" : "en"
        locale = Locale.current.language.languageCode?.identifier == wanted ? Locale.current : Locale(identifier: isDutch ? "nl_NL" : "en_US")
        self.language = language // notifies SwiftUI
    }

    private static let english: [String: String] = [
        "popup.search": "Search clipboard…",
        "popup.empty": "Nothing copied yet. Everything you copy with ⌘C shows up here.",
        "popup.noResults": "No results",
        "popup.pin.tooltip": "Pin or unpin (⌘P)",
        "popup.remove.tooltip": "Remove (⌘⌫)",
        "popup.undo": "Removed · ⌘Z to undo",
        "popup.preview.more": "\n… and {0} more characters",
        "popup.copied.now": "Copied just now",
        "popup.copied.minutes": "Copied {0} min ago",
        "popup.copied.today": "Copied today at {0}",
        "popup.copied.yesterday": "Copied yesterday at {0}",
        "popup.copied.date": "Copied on {0} at {1}",
        "popup.formatting": "With formatting, ⌘↩ pastes plain text",
        "popup.imageText": "⌘↩ pastes the text in the image",
        "item.files": "{0} files: ",
        "item.image": "Image, {0} × {1}",
        "key.space": "Space",

        "tray.open": "Open Pastebird",
        "tray.clear": "Clear History",
        "tray.settings": "Settings…",
        "tray.exit": "Quit Pastebird",
        "tray.update": "Update to Version {0}",

        "notify.running.title": "Pastebird is running in the menu bar",
        "notify.running.text": "Press {0} to open your clipboard history.",
        "notify.hotkey.title": "Shortcut not available",
        "notify.hotkey.text": "{0} is already used by another app. Choose a different shortcut in Settings.",
        "notify.update.title": "Update available",
        "notify.update.text": "Pastebird {0} is available. Click here to update.",
        "notify.updating.title": "Updating Pastebird…",
        "notify.updating.text": "Pastebird restarts by itself in a moment.",
        "notify.updatefailed.title": "Update failed",
        "notify.updatefailed.text": "Click here to download the new version from GitHub.",
        "notify.paste.title": "Allow Pastebird to paste",
        "notify.paste.text": "The item is on the clipboard: press ⌘V. To paste automatically, turn on Pastebird in System Settings → Privacy & Security → Accessibility.",
        "clear.confirm": "Do you want to clear the clipboard history?",
        "clear.confirm.detail": "Pinned items stay.",
        "clear.confirm.yes": "Clear",
        "clear.confirm.no": "Cancel",

        "settings.title": "Pastebird Settings",
        "settings.autostart": "Open at login",
        "settings.autostart.desc": "Pastebird starts automatically in the menu bar when you log in.",
        "settings.autostart.denied": "macOS needs your approval: turn on Pastebird in System Settings → General → Login Items.",
        "settings.autopaste": "Paste automatically",
        "settings.autopaste.desc": "Paste the chosen item straight into the app you were in. ⇧↩ only copies.",
        "settings.autopaste.permission": "macOS needs your permission for this: turn on Pastebird in Privacy & Security → Accessibility.",
        "settings.autopaste.open": "Open System Settings",
        "settings.hotkey": "Shortcut",
        "settings.hotkey.desc": "Click and choose a new combination.",
        "settings.hotkey.press": "Press keys…",
        "settings.hotkey.modifier": "Use at least ⌘, ⌥ or ⌃ in the combination.",
        "settings.hotkey.taken": "{0} is already used by another app.",
        "settings.history": "History",
        "settings.history.desc": "Number of items Pastebird remembers, not counting pinned items. At most 50 of them are images.",
        "settings.history.items": "{0} items",
        "settings.keep": "Remove old items",
        "settings.keep.desc": "Removes items you copied longer ago, except pinned ones.",
        "settings.keep.always": "Never",
        "settings.keep.day": "After 1 day",
        "settings.keep.days": "After {0} days",
        "settings.updates": "Check for updates automatically",
        "settings.updates.desc": "Once a day, Pastebird asks GitHub whether there is a new version. Nothing about you or your clipboard is sent.",
        "settings.updates.check": "Check Now",
        "settings.updates.checking": "Checking…",
        "settings.updates.current": "You have the latest version.",
        "settings.updates.offline": "Couldn't reach GitHub. Try again later.",
        "settings.updates.available": "Version {0} is available.",
        "settings.updates.install": "Update Now",
        "settings.updates.installing": "Downloading update…",
        "settings.updates.failed": "Update failed. Try again or download it from GitHub.",
        "settings.clear": "Clear history",
        "settings.clear.desc": "Removes all saved clipboard items except pinned ones.",
        "settings.clear.button": "Clear…",
        "settings.language": "Language",
        "settings.language.desc": "Language of Pastebird's menus and windows.",
        "settings.language.system": "System default",

        "about.title": "About",
        "about.version": "Version {0}",
        "about.license": "MIT license",
        "about.createdBy": "Created by Patrick Speters",
        "about.local": "All data stays on this Mac. No account, no cloud, no tracking.",
        "about.github": "Source Code on GitHub",
        "about.donate": "Buy Me a Coffee",
        "about.whatsnew": "What's New",

        "notify.updated.title": "Pastebird is updated to version {0}",
        "notify.updated.text": "Click here to see what's new.",
        "whatsnew.title": "What's new in Pastebird",
        "whatsnew.updated": "Updated to version {0}",
        "whatsnew.english": "",
        "whatsnew.empty": "No changes to show.",
        "whatsnew.all": "All Changes",
        "whatsnew.close": "Close",
        "whatsnew.culture": "en_US",
        "whatsnew.type.added": "New",
        "whatsnew.type.changed": "Changed",
        "whatsnew.type.fixed": "Fixed",
        "whatsnew.type.removed": "Removed",
        "whatsnew.type.security": "Security",
    ]

    private static let dutch: [String: String] = [
        "popup.search": "Zoeken in klembord…",
        "popup.empty": "Nog niets gekopieerd. Alles wat je kopieert met ⌘C verschijnt hier.",
        "popup.noResults": "Geen resultaten",
        "popup.pin.tooltip": "Vastpinnen of losmaken (⌘P)",
        "popup.remove.tooltip": "Verwijderen (⌘⌫)",
        "popup.undo": "Verwijderd · ⌘Z zet terug",
        "popup.preview.more": "\n… en nog {0} tekens",
        "popup.copied.now": "Zojuist gekopieerd",
        "popup.copied.minutes": "{0} min geleden gekopieerd",
        "popup.copied.today": "Vandaag om {0} gekopieerd",
        "popup.copied.yesterday": "Gisteren om {0} gekopieerd",
        "popup.copied.date": "Op {0} om {1} gekopieerd",
        "popup.formatting": "Met opmaak, ⌘↩ plakt platte tekst",
        "popup.imageText": "⌘↩ plakt de tekst in de afbeelding",
        "item.files": "{0} bestanden: ",
        "item.image": "Afbeelding, {0} × {1}",
        "key.space": "Spatie",

        "tray.open": "Open Pastebird",
        "tray.clear": "Geschiedenis wissen",
        "tray.settings": "Instellingen…",
        "tray.exit": "Stop Pastebird",
        "tray.update": "Bijwerken naar versie {0}",

        "notify.running.title": "Pastebird staat in de menubalk",
        "notify.running.text": "Druk op {0} om je klembordgeschiedenis te openen.",
        "notify.hotkey.title": "Sneltoets niet beschikbaar",
        "notify.hotkey.text": "{0} wordt al door een andere app gebruikt. Kies een andere sneltoets via Instellingen.",
        "notify.update.title": "Update beschikbaar",
        "notify.update.text": "Pastebird {0} is beschikbaar. Klik hier om bij te werken.",
        "notify.updating.title": "Pastebird wordt bijgewerkt…",
        "notify.updating.text": "Pastebird start zo vanzelf opnieuw.",
        "notify.updatefailed.title": "Bijwerken mislukt",
        "notify.updatefailed.text": "Klik hier om de nieuwe versie van GitHub te downloaden.",
        "notify.paste.title": "Geef Pastebird toestemming om te plakken",
        "notify.paste.text": "Het item staat op het klembord: druk op ⌘V. Om automatisch te plakken zet je Pastebird aan in Systeeminstellingen → Privacy en beveiliging → Toegankelijkheid.",
        "clear.confirm": "Wil je de klembordgeschiedenis wissen?",
        "clear.confirm.detail": "Vastgepinde items blijven bewaard.",
        "clear.confirm.yes": "Wissen",
        "clear.confirm.no": "Annuleer",

        "settings.title": "Pastebird-instellingen",
        "settings.autostart": "Open bij inloggen",
        "settings.autostart.desc": "Pastebird start automatisch in de menubalk na het inloggen.",
        "settings.autostart.denied": "macOS vraagt je toestemming: zet Pastebird aan in Systeeminstellingen → Algemeen → Inlogonderdelen.",
        "settings.autopaste": "Automatisch plakken",
        "settings.autopaste.desc": "Plak het gekozen item direct in de app waar je was. ⇧↩ kopieert alleen.",
        "settings.autopaste.permission": "macOS vraagt hiervoor je toestemming: zet Pastebird aan in Privacy en beveiliging → Toegankelijkheid.",
        "settings.autopaste.open": "Open Systeeminstellingen",
        "settings.hotkey": "Sneltoets",
        "settings.hotkey.desc": "Klik en kies een nieuwe combinatie.",
        "settings.hotkey.press": "Druk op toetsen…",
        "settings.hotkey.modifier": "Gebruik minstens ⌘, ⌥ of ⌃ in de combinatie.",
        "settings.hotkey.taken": "{0} is al in gebruik door een andere app.",
        "settings.history": "Geschiedenis",
        "settings.history.desc": "Aantal items dat Pastebird onthoudt, vastgepinde niet meegeteld. Daarvan zijn er maximaal 50 afbeeldingen.",
        "settings.history.items": "{0} items",
        "settings.keep": "Oude items verwijderen",
        "settings.keep.desc": "Verwijdert items die je langer geleden kopieerde, behalve vastgepinde.",
        "settings.keep.always": "Nooit",
        "settings.keep.day": "Na 1 dag",
        "settings.keep.days": "Na {0} dagen",
        "settings.updates": "Automatisch op updates controleren",
        "settings.updates.desc": "Pastebird vraagt één keer per dag aan GitHub of er een nieuwe versie is. Er wordt niets over jou of je klembord verstuurd.",
        "settings.updates.check": "Nu controleren",
        "settings.updates.checking": "Controleren…",
        "settings.updates.current": "Je hebt de nieuwste versie.",
        "settings.updates.offline": "GitHub is niet bereikbaar. Probeer het later opnieuw.",
        "settings.updates.available": "Versie {0} is beschikbaar.",
        "settings.updates.install": "Nu bijwerken",
        "settings.updates.installing": "Update downloaden…",
        "settings.updates.failed": "Bijwerken mislukt. Probeer het opnieuw of download hem van GitHub.",
        "settings.clear": "Geschiedenis wissen",
        "settings.clear.desc": "Verwijdert alle bewaarde klembord-items, behalve vastgepinde.",
        "settings.clear.button": "Wissen…",
        "settings.language": "Taal",
        "settings.language.desc": "Taal van de menu's en vensters van Pastebird.",
        "settings.language.system": "Systeemstandaard",

        "about.title": "Over Pastebird",
        "about.version": "Versie {0}",
        "about.license": "MIT-licentie",
        "about.createdBy": "Gemaakt door Patrick Speters",
        "about.local": "Alle gegevens blijven op deze Mac. Geen account, geen cloud, geen tracking.",
        "about.github": "Broncode op GitHub",
        "about.donate": "Trakteer me op een koffie",
        "about.whatsnew": "Wat is er nieuw",

        "notify.updated.title": "Pastebird is bijgewerkt naar versie {0}",
        "notify.updated.text": "Klik hier om te zien wat er nieuw is.",
        "whatsnew.title": "Wat is er nieuw in Pastebird",
        "whatsnew.updated": "Bijgewerkt naar versie {0}",
        "whatsnew.english": "De wijzigingen zijn in het Engels beschreven.",
        "whatsnew.empty": "Geen wijzigingen om te tonen.",
        "whatsnew.all": "Alle wijzigingen",
        "whatsnew.close": "Sluiten",
        "whatsnew.culture": "nl_NL",
        "whatsnew.type.added": "Nieuw",
        "whatsnew.type.changed": "Gewijzigd",
        "whatsnew.type.fixed": "Opgelost",
        "whatsnew.type.removed": "Verwijderd",
        "whatsnew.type.security": "Beveiliging",
    ]
}
