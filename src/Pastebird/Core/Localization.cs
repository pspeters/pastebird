using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Text.Json;

namespace Pastebird.Core;

/// <summary>A UI language: its code (the file name, e.g. "nl" or "pt-BR") and its name in that language.</summary>
public sealed record UiLanguage(string Code, string Name);

/// <summary>
/// UI strings, one JSON file per language in Languages\ (see docs/TRANSLATING.md). XAML binds to the indexer
/// (<c>{Binding [key], Source={x:Static core:Loc.Instance}}</c>), so switching language updates open windows
/// immediately. Code uses <see cref="T(string)"/>. Missing strings fall back to English. Keys ending in ".mac"
/// are for the Mac version, which reads the same files.
/// </summary>
public sealed class Loc : INotifyPropertyChanged
{
    private const string FallbackCode = "en";

    private static readonly Dictionary<string, Dictionary<string, string>> Packs = LoadPacks();
    private static readonly Dictionary<string, string> English = Packs[FallbackCode];

    private Dictionary<string, string> _strings = English;

    // Lazy, so the static fields above are initialized before the instance reads them.
    public static Loc Instance => _instance ??= new Loc();
    private static Loc? _instance;

    public event PropertyChangedEventHandler? PropertyChanged;

    public string this[string key] => _strings.TryGetValue(key, out var s) ? s : English.GetValueOrDefault(key, key);

    public static string T(string key) => Instance[key];

    public static string T(string key, params object[] args) => string.Format(Instance[key], args);

    /// <summary>All languages Pastebird can show, sorted by name.</summary>
    public static IReadOnlyList<UiLanguage> Languages { get; } = Packs
        .Select(p => new UiLanguage(p.Key, p.Value.GetValueOrDefault("language.name", p.Key)))
        .OrderBy(l => l.Name, StringComparer.CurrentCultureIgnoreCase)
        .ToList();

    /// <summary>Culture for dates in the UI: the system's when it matches the UI language, otherwise a default for that language.</summary>
    public static CultureInfo Culture { get; private set; } = CultureInfo.CurrentCulture;

    /// <summary>Switches to the language with this code; null (or a language that isn't there) follows Windows.</summary>
    public static void Apply(string? language)
    {
        var code = Resolve(language);
        Instance._strings = Packs[code];

        var specific = CultureInfo.CreateSpecificCulture(code);
        Culture = CultureInfo.CurrentCulture.TwoLetterISOLanguageName == specific.TwoLetterISOLanguageName
            ? CultureInfo.CurrentCulture
            : specific;
        Instance.PropertyChanged?.Invoke(Instance, new PropertyChangedEventArgs("Item[]"));
    }

    private static string Resolve(string? language)
    {
        if (!string.IsNullOrEmpty(language) && Packs.ContainsKey(language))
            return Packs.Keys.First(k => k.Equals(language, StringComparison.OrdinalIgnoreCase));

        // The Windows display language: exactly ("pt-BR") or just the language ("nl-BE" → "nl").
        var ui = CultureInfo.CurrentUICulture;
        foreach (var candidate in new[] { ui.Name, ui.TwoLetterISOLanguageName })
        {
            if (Packs.Keys.FirstOrDefault(k => k.Equals(candidate, StringComparison.OrdinalIgnoreCase)) is { } code)
                return code;
        }
        return FallbackCode;
    }

    /// <summary>
    /// The languages built into Pastebird, plus files in %LOCALAPPDATA%\Pastebird\Languages, so a translator
    /// can try a translation without building Pastebird. Such a file adds to or overrides a built-in language.
    /// </summary>
    private static Dictionary<string, Dictionary<string, string>> LoadPacks()
    {
        var packs = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);

        var assembly = typeof(Loc).Assembly;
        foreach (var name in assembly.GetManifestResourceNames())
        {
            if (!name.StartsWith("Languages.", StringComparison.Ordinal) || !name.EndsWith(".json", StringComparison.Ordinal)) continue;
            using var stream = assembly.GetManifestResourceStream(name)!;
            Add(name["Languages.".Length..^".json".Length], stream);
        }

        try
        {
            var folder = Path.Combine(LocalStorage.Folder, "Languages");
            if (Directory.Exists(folder))
            {
                foreach (var file in Directory.EnumerateFiles(folder, "*.json"))
                {
                    try
                    {
                        using var stream = File.OpenRead(file);
                        Add(Path.GetFileNameWithoutExtension(file), stream);
                    }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
                    {
                        LocalStorage.Log(ex);
                    }
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            LocalStorage.Log(ex);
        }

        return packs;

        void Add(string code, Stream stream)
        {
            if (!IsCulture(code)) return;
            var strings = JsonSerializer.Deserialize(stream, PastebirdJson.Default.DictionaryStringString) ?? [];
            if (packs.TryGetValue(code, out var existing))
            {
                foreach (var (key, value) in strings)
                    existing[key] = value;
            }
            else
            {
                packs[code] = strings;
            }
        }
    }

    private static bool IsCulture(string code)
    {
        try { return CultureInfo.GetCultureInfo(code, predefinedOnly: true).Name.Length > 0; }
        catch (CultureNotFoundException) { return false; }
    }
}
