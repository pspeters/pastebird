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

    private static readonly byte[] DataEntropy = "Pastebird.Data.v1"u8.ToArray();

    private static string HistoryPath => Path.Combine(Folder, "history.dat");
    private static string DataFolder => Path.Combine(Folder, "data");
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

    /// <summary>Saves the history and removes the <see cref="ClipData"/> files of items that are no longer in it.</summary>
    public void SaveHistory(IEnumerable<ClipItem> items)
    {
        try
        {
            var list = items.ToList();
            var json = JsonSerializer.SerializeToUtf8Bytes(list, PastebirdJson.Default.ListClipItem);
            WriteAtomic(HistoryPath, ProtectedData.Protect(json, Entropy, DataProtectionScope.CurrentUser));
            RemoveUnusedData(list);
        }
        catch (Exception ex)
        {
            Log(ex);
        }
    }

    /// <summary>Stores the formatting or image of an item (encrypted like the history), or removes it when there is none.</summary>
    public void SaveData(ClipItem item, ClipData? data)
    {
        try
        {
            if (data is null)
            {
                File.Delete(DataPath(item.Id));
                return;
            }
            Directory.CreateDirectory(DataFolder);
            WriteAtomic(DataPath(item.Id), ProtectedData.Protect(data.Serialize(), DataEntropy, DataProtectionScope.CurrentUser));
        }
        catch (Exception ex)
        {
            Log(ex);
        }
    }

    public ClipData? LoadData(ClipItem item)
    {
        if (!item.HasData) return null;
        try
        {
            var path = DataPath(item.Id);
            if (!File.Exists(path)) return null;
            return ClipData.Deserialize(ProtectedData.Unprotect(File.ReadAllBytes(path), DataEntropy, DataProtectionScope.CurrentUser));
        }
        catch (Exception ex)
        {
            Log(ex);
            return null;
        }
    }

    private static string DataPath(Guid id) => Path.Combine(DataFolder, id.ToString("N") + ".dat");

    private static void RemoveUnusedData(List<ClipItem> items)
    {
        if (!Directory.Exists(DataFolder)) return;
        var used = items.Where(i => i.HasData).Select(i => i.Id.ToString("N")).ToHashSet();
        foreach (var file in Directory.EnumerateFiles(DataFolder))
        {
            if (!used.Contains(Path.GetFileNameWithoutExtension(file)))
                File.Delete(file);
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
