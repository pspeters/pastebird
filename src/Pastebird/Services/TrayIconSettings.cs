using System.IO;
using Microsoft.Win32;
using Pastebird.Core;

namespace Pastebird.Services;

/// <summary>
/// Windows remembers per program path whether a tray icon shows on the taskbar or behind the arrow. The Microsoft
/// Store installs every version in its own folder (…\WindowsApps\Name_1.8.1.0_x64__publisher\Pastebird.exe),
/// so after an update Windows sees a new program and hides the icon. Pastebird can't change that: Explorer only
/// reads these settings when it starts, and a Store app can't write them. It can tell the user, though.
/// </summary>
internal static class TrayIconSettings
{
    private const string KeyPath = @"Control Panel\NotifyIconSettings";

    /// <summary>True when the icon was on the taskbar in the previous version and isn't in this one.</summary>
    public static bool WasHiddenByUpdate()
    {
        try
        {
            if (PackageFolder.Parse(Path.GetDirectoryName(Environment.ProcessPath)) is not { } current) return false;

            using var root = Registry.CurrentUser.OpenSubKey(KeyPath);
            if (root is null) return false;

            bool currentPromoted = false;
            (Version Version, bool Promoted)? previous = null;
            foreach (var name in root.GetSubKeyNames())
            {
                using var entry = root.OpenSubKey(name);
                if (entry?.GetValue("ExecutablePath") is not string path) continue;
                if (!Path.GetFileName(path).Equals(Path.GetFileName(Environment.ProcessPath), StringComparison.OrdinalIgnoreCase)) continue;
                if (PackageFolder.Parse(Path.GetDirectoryName(path)) is not { } folder || !folder.IsSameApp(current)) continue;

                bool promoted = entry.GetValue("IsPromoted") is 1;
                if (folder.Version == current.Version)
                    currentPromoted = promoted;
                else if (folder.Version < current.Version && (previous is null || folder.Version > previous.Value.Version))
                    previous = (folder.Version, promoted);
            }
            // A version Windows hasn't seen yet has no entry, and new icons go behind the arrow.
            return previous is { Promoted: true } && !currentPromoted;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            LocalStorage.Log(ex);
            return false;
        }
    }

    /// <summary>A package folder name: Name_Version_Architecture__PublisherId.</summary>
    private sealed record PackageFolder(string Name, Version Version, string PublisherId)
    {
        public bool IsSameApp(PackageFolder other) =>
            Name.Equals(other.Name, StringComparison.OrdinalIgnoreCase) && PublisherId.Equals(other.PublisherId, StringComparison.OrdinalIgnoreCase);

        public static PackageFolder? Parse(string? directory)
        {
            var parts = Path.GetFileName(directory ?? "").Split('_');
            // "Name", "1.8.1.0", "x64", "", "publisherid"
            if (parts.Length != 5 || parts[3].Length != 0 || !Version.TryParse(parts[1], out var version)) return null;
            return new PackageFolder(parts[0], version, parts[4]);
        }
    }
}
