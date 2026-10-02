using System.Windows.Input;
using static Pastebird.Interop.NativeMethods;

namespace Pastebird.Core;

/// <summary>A global shortcut as Win32 modifier flags (MOD_*) plus a virtual-key code.</summary>
public readonly record struct Hotkey(int Modifiers, int VirtualKey)
{
    public static readonly Hotkey Default = new(MOD_CONTROL | MOD_SHIFT, 0x56); // Ctrl + Shift + V

    public bool IsValid => VirtualKey != 0 && (Modifiers & (MOD_CONTROL | MOD_ALT | MOD_WIN)) != 0;

    public static Hotkey FromWpf(ModifierKeys modifiers, Key key)
    {
        int mods = 0;
        if (modifiers.HasFlag(ModifierKeys.Control)) mods |= MOD_CONTROL;
        if (modifiers.HasFlag(ModifierKeys.Alt)) mods |= MOD_ALT;
        if (modifiers.HasFlag(ModifierKeys.Shift)) mods |= MOD_SHIFT;
        if (modifiers.HasFlag(ModifierKeys.Windows)) mods |= MOD_WIN;
        return new Hotkey(mods, KeyInterop.VirtualKeyFromKey(key));
    }

    public override string ToString()
    {
        var parts = new List<string>(5);
        if ((Modifiers & MOD_CONTROL) != 0) parts.Add("Ctrl");
        if ((Modifiers & MOD_ALT) != 0) parts.Add("Alt");
        if ((Modifiers & MOD_SHIFT) != 0) parts.Add("Shift");
        if ((Modifiers & MOD_WIN) != 0) parts.Add("Win");
        parts.Add(KeyName(KeyInterop.KeyFromVirtualKey(VirtualKey)));
        return string.Join(" + ", parts);
    }

    private static string KeyName(Key key) => key switch
    {
        >= Key.D0 and <= Key.D9 => ((char)('0' + (key - Key.D0))).ToString(),
        Key.Space => Loc.T("key.space"),
        Key.Insert => "Ins",
        Key.OemPeriod => ".",
        Key.OemComma => ",",
        Key.OemMinus => "-",
        Key.OemPlus => "=",
        _ => key.ToString(),
    };
}
