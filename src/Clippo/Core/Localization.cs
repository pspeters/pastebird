using System.ComponentModel;
using System.Globalization;

namespace Clippo.Core;

public enum AppLanguage { System, English, Dutch }

/// <summary>
/// UI strings in English and Dutch. XAML binds to the indexer (<c>{Binding [key], Source={x:Static core:Loc.Instance}}</c>),
/// so switching language updates open windows immediately. Code uses <see cref="T(string)"/>.
/// </summary>
public sealed class Loc : INotifyPropertyChanged
{
    private Dictionary<string, string> _strings = English;

    // Lazy, so the static dictionaries below are initialized before the instance reads them.
    public static Loc Instance => _instance ??= new Loc();
    private static Loc? _instance;

    public event PropertyChangedEventHandler? PropertyChanged;

    public string this[string key] => _strings.TryGetValue(key, out var s) ? s : English.GetValueOrDefault(key, key);

    public static string T(string key) => Instance[key];

    public static string T(string key, params object[] args) => string.Format(Instance[key], args);

    public static void Apply(AppLanguage language)
    {
        bool dutch = language == AppLanguage.Dutch
            || (language == AppLanguage.System && CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "nl");
        Instance._strings = dutch ? Dutch : English;
        Instance.PropertyChanged?.Invoke(Instance, new PropertyChangedEventArgs("Item[]"));
    }

    private static readonly Dictionary<string, string> English = new()
    {
        ["popup.search"] = "Search clipboard…",
        ["popup.empty"] = "Nothing copied yet. Everything you copy with Ctrl+C shows up here.",
        ["popup.noResults"] = "No results",
        ["item.files"] = "{0} files: ",
        ["key.space"] = "Space",

        ["tray.open"] = "Open Clippo",
        ["tray.clear"] = "Clear history",
        ["tray.settings"] = "Settings",
        ["tray.exit"] = "Exit",

        ["notify.running.title"] = "Clippo is running in the background",
        ["notify.running.text"] = "Press {0} to open your clipboard history.",
        ["notify.hotkey.title"] = "Shortcut not available",
        ["notify.hotkey.text"] = "{0} is already used by another program. Choose a different shortcut in Settings.",
        ["clear.confirm"] = "Do you want to clear the entire clipboard history?",

        ["settings.title"] = "Clippo settings",
        ["settings.autostart"] = "Start with Windows",
        ["settings.autostart.desc"] = "Clippo starts automatically in the background when you sign in.",
        ["settings.autostart.denied"] = "Windows doesn't allow this. Turn Clippo on in Task Manager → Startup apps.",
        ["settings.autopaste"] = "Paste automatically",
        ["settings.autopaste.desc"] = "Paste the chosen item straight into the window you were in. Shift\u2060+\u2060Enter only copies.",
        ["settings.hotkey"] = "Shortcut",
        ["settings.hotkey.desc"] = "Click and choose a new combination.",
        ["settings.hotkey.press"] = "Press keys…",
        ["settings.hotkey.modifier"] = "Use at least Ctrl, Alt or Win in the combination.",
        ["settings.hotkey.taken"] = "{0} is already used by another program.",
        ["settings.history"] = "History",
        ["settings.history.desc"] = "Number of items Clippo remembers.",
        ["settings.history.items"] = "{0} items",
        ["settings.clear"] = "Clear history",
        ["settings.clear.desc"] = "Removes all saved clipboard items.",
        ["settings.clear.button"] = "Clear…",
        ["settings.language"] = "Language",
        ["settings.language.desc"] = "Language of Clippo's menus and windows.",
        ["settings.language.system"] = "System default",

        ["about.title"] = "About",
        ["about.version"] = "Version {0}",
        ["about.license"] = "MIT license",
        ["about.createdBy"] = "Created by Patrick Speters",
        ["about.local"] = "All data stays on this pc. No account, no cloud, no tracking.",
        ["about.github"] = "Source code on GitHub",
        ["about.donate"] = "Buy me a coffee",
    };

    private static readonly Dictionary<string, string> Dutch = new()
    {
        ["popup.search"] = "Zoeken in klembord…",
        ["popup.empty"] = "Nog niets gekopieerd. Alles wat je kopieert met Ctrl+C verschijnt hier.",
        ["popup.noResults"] = "Geen resultaten",
        ["item.files"] = "{0} bestanden: ",
        ["key.space"] = "Spatie",

        ["tray.open"] = "Open Clippo",
        ["tray.clear"] = "Geschiedenis wissen",
        ["tray.settings"] = "Instellingen",
        ["tray.exit"] = "Afsluiten",

        ["notify.running.title"] = "Clippo draait op de achtergrond",
        ["notify.running.text"] = "Druk op {0} om je klembordgeschiedenis te openen.",
        ["notify.hotkey.title"] = "Sneltoets niet beschikbaar",
        ["notify.hotkey.text"] = "{0} wordt al door een ander programma gebruikt. Kies een andere sneltoets via Instellingen.",
        ["clear.confirm"] = "Wil je de volledige clipboardgeschiedenis wissen?",

        ["settings.title"] = "Clippo-instellingen",
        ["settings.autostart"] = "Starten met Windows",
        ["settings.autostart.desc"] = "Clippo start automatisch op de achtergrond na het aanmelden.",
        ["settings.autostart.denied"] = "Windows staat dit niet toe. Zet Clippo aan via Taakbeheer → Opstart-apps.",
        ["settings.autopaste"] = "Automatisch plakken",
        ["settings.autopaste.desc"] = "Plak het gekozen item direct in het venster waar je was. Shift\u2060+\u2060Enter kopieert alleen.",
        ["settings.hotkey"] = "Sneltoets",
        ["settings.hotkey.desc"] = "Klik en kies een nieuwe combinatie.",
        ["settings.hotkey.press"] = "Druk op toetsen…",
        ["settings.hotkey.modifier"] = "Gebruik minstens Ctrl, Alt of Win in de combinatie.",
        ["settings.hotkey.taken"] = "{0} is al in gebruik door een ander programma.",
        ["settings.history"] = "Geschiedenis",
        ["settings.history.desc"] = "Aantal items dat Clippo onthoudt.",
        ["settings.history.items"] = "{0} items",
        ["settings.clear"] = "Geschiedenis wissen",
        ["settings.clear.desc"] = "Verwijdert alle bewaarde clipboard-items.",
        ["settings.clear.button"] = "Wissen…",
        ["settings.language"] = "Taal",
        ["settings.language.desc"] = "Taal van de menu's en vensters van Clippo.",
        ["settings.language.system"] = "Systeemstandaard",

        ["about.title"] = "Over Clippo",
        ["about.version"] = "Versie {0}",
        ["about.license"] = "MIT-licentie",
        ["about.createdBy"] = "Gemaakt door Patrick Speters",
        ["about.local"] = "Alle gegevens blijven op deze pc. Geen account, geen cloud, geen tracking.",
        ["about.github"] = "Broncode op GitHub",
        ["about.donate"] = "Trakteer me op een koffie",
    };
}
