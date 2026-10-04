using System.Text.Json.Serialization;

namespace Pastebird.Core;

/// <summary>The few user settings Pastebird has. Defaults are chosen so nobody needs to open Settings.</summary>
public sealed class AppSettings
{
    public static readonly int[] HistorySizes = [50, 100, 200, 500];

    public bool StartWithWindows { get; set; } = true;
    public bool PasteAutomatically { get; set; } = true;
    public bool CheckForUpdates { get; set; } = true;

    /// <summary>Version that ran last time; a lower value means Pastebird was just updated.</summary>
    public string? LastRunVersion { get; set; }
    public int MaxItems { get; set; } = 200;
    public AppLanguage Language { get; set; } = AppLanguage.System;
    public int HotkeyModifiers { get; set; } = Hotkey.Default.Modifiers;
    public int HotkeyKey { get; set; } = Hotkey.Default.VirtualKey;

    [JsonIgnore]
    public Hotkey Hotkey
    {
        get => new(HotkeyModifiers, HotkeyKey);
        set { HotkeyModifiers = value.Modifiers; HotkeyKey = value.VirtualKey; }
    }

    public AppSettings Normalize()
    {
        if (!HistorySizes.Contains(MaxItems)) MaxItems = 200;
        if (!Hotkey.IsValid) Hotkey = Hotkey.Default;
        if (!Enum.IsDefined(Language)) Language = AppLanguage.System;
        return this;
    }
}
