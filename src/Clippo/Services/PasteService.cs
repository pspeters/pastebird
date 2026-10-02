using System.Runtime.InteropServices;
using System.Text;
using static Clippo.Interop.NativeMethods;

namespace Clippo.Services;

/// <summary>
/// Remembers which window was active before Clippo opened and sends Ctrl+V to it after a choice.
/// Pasting is skipped (the item simply stays on the clipboard) whenever it cannot be done safely.
/// </summary>
internal static class PasteService
{
    private static readonly HashSet<string> ShellClasses =
    [
        "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow",
        "TopLevelWindowForOverflowXamlIsland", "Progman", "WorkerW",
    ];

    /// <summary>Returns the current foreground window if it is a sensible paste target, otherwise zero.</summary>
    public static IntPtr CaptureTarget()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return IntPtr.Zero;

        GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == Environment.ProcessId) return IntPtr.Zero;

        var name = new StringBuilder(256);
        GetClassName(hwnd, name, name.Capacity);
        return ShellClasses.Contains(name.ToString()) ? IntPtr.Zero : hwnd;
    }

    public static async Task PasteAsync(IntPtr target)
    {
        if (target == IntPtr.Zero || !IsWindow(target)) return;

        SetForegroundWindow(target);

        // Wait until the target is active and the user has released Ctrl/Shift/Alt/Win.
        for (int i = 0; i < 30 && (GetForegroundWindow() != target || ModifiersDown()); i++)
            await Task.Delay(20);
        if (GetForegroundWindow() != target || ModifiersDown())
            return;

        await Task.Delay(30); // let the target restore focus to its input control

        var inputs = new[]
        {
            Key(0x11, false), Key(0x56, false), // Ctrl down, V down
            Key(0x56, true), Key(0x11, true),   // V up, Ctrl up
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static bool ModifiersDown()
    {
        foreach (int vk in (int[])[0x10, 0x11, 0x12, 0x5B, 0x5C]) // Shift, Ctrl, Alt, LWin, RWin
            if ((GetAsyncKeyState(vk) & 0x8000) != 0) return true;
        return false;
    }

    private static INPUT Key(ushort vk, bool up) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = up ? KEYEVENTF_KEYUP : 0 } },
    };
}
