using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Pastebird.Core;

/// <summary>
/// Stores everything under %LOCALAPPDATA%\Pastebird (per user, not roaming, not synced).
/// The history is additionally encrypted with DPAPI for the current Windows user,
/// so the file is unreadable for other accounts and off this machine.
/// </summary>
public sealed class LocalStorage
{
    public static readonly string Folder =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Pastebird");

    private static readonly byte[] Entropy = "Pastebird.History.v1"u8.ToArray();

    private static string HistoryPath => Path.Combine(Folder, "history.dat");
    private static string SettingsPath => Path.Combine(Folder, "settings.json");

    public LocalStorage() => Directory.CreateDirectory(Folder);

    public bool SettingsExist => File.Exists(SettingsPath);

    public List<ClipItem> LoadHistory()
    {
        try
        {
            if (!File.Exists(HistoryPath)) return [];
            var json = ProtectedData.Unprotect(File.ReadAllBytes(HistoryPath), Entropy, DataProtectionScope.CurrentUser);
            return JsonSerializer.Deserialize(json, PastebirdJson.Default.ListClipItem) ?? [];
        }
        catch (Exception ex)
        {
            Log(ex);
            return [];
        }
    }

    public void SaveHistory(IEnumerable<ClipItem> items)
    {
        try
        {
            var json = JsonSerializer.SerializeToUtf8Bytes(items.ToList(), PastebirdJson.Default.ListClipItem);
            WriteAtomic(HistoryPath, ProtectedData.Protect(json, Entropy, DataProtectionScope.CurrentUser));
        }
        catch (Exception ex)
        {
            Log(ex);
        }
    }

    public AppSettings LoadSettings()
    {
        try
        {
            if (File.Exists(SettingsPath))
                return (JsonSerializer.Deserialize(File.ReadAllBytes(SettingsPath), PastebirdJson.Default.AppSettings) ?? new()).Normalize();
        }
        catch (Exception ex)
        {
            Log(ex);
        }
        return new AppSettings();
    }

    public void SaveSettings(AppSettings settings)
    {
        try
        {
            WriteAtomic(SettingsPath, JsonSerializer.SerializeToUtf8Bytes(settings, PastebirdJson.Default.AppSettings));
        }
        catch (Exception ex)
        {
            Log(ex);
        }
    }

    public static void Log(Exception ex)
    {
        try
        {
            Directory.CreateDirectory(Folder);
            var path = Path.Combine(Folder, "error.log");
            if (File.Exists(path) && new FileInfo(path).Length > 256 * 1024) File.Delete(path);
            File.AppendAllText(path, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {ex}{Environment.NewLine}");
        }
        catch
        {
            // Logging must never take the app down.
        }
    }

    private static void WriteAtomic(string path, byte[] data)
    {
        var temp = path + ".tmp";
        File.WriteAllBytes(temp, data);
        File.Move(temp, path, overwrite: true);
    }
}

[JsonSourceGenerationOptions(WriteIndented = true, UseStringEnumConverter = true)]
[JsonSerializable(typeof(List<ClipItem>))]
[JsonSerializable(typeof(AppSettings))]
internal partial class PastebirdJson : JsonSerializerContext;
