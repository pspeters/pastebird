using System.Text.Json.Serialization;

namespace Clippo.Core;

/// <summary>The few user settings Clippo has. Defaults are chosen so nobody needs to open Settings.</summary>
public sealed class AppSettings
{
    public static readonly int[] HistorySizes = [50, 100, 200, 500];

    public bool StartWithWindows { get; set; } = true;
    public bool PasteAutomatically { get; set; } = true;
    public int MaxItems { get; set; } = 200;
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
        return this;
    }
}
