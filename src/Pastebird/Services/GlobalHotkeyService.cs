using Pastebird.Core;
using static Pastebird.Interop.NativeMethods;

namespace Pastebird.Services;

/// <summary>Registers one system-wide shortcut (RegisterHotKey) on the message window.</summary>
internal sealed class GlobalHotkeyService : IDisposable
{
    private const int HotkeyId = 0xC11;

    private readonly MessageWindow _window;
    private bool _registered;

    public GlobalHotkeyService(MessageWindow window)
    {
        _window = window;
        _window.Message += OnMessage;
    }

    public event Action? Pressed;

    public bool IsRegistered => _registered;

    /// <summary>Replaces the current shortcut. Returns false if another app already owns it.</summary>
    public bool Register(Hotkey hotkey)
    {
        Unregister();
        _registered = RegisterHotKey(_window.Handle, HotkeyId, (uint)(hotkey.Modifiers | MOD_NOREPEAT), (uint)hotkey.VirtualKey);
        return _registered;
    }

    public void Unregister()
    {
        if (!_registered) return;
        UnregisterHotKey(_window.Handle, HotkeyId);
        _registered = false;
    }

    private void OnMessage(int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg != WM_HOTKEY || wParam != HotkeyId) return;
        handled = true;
        Pressed?.Invoke();
    }

    public void Dispose()
    {
        Unregister();
        _window.Message -= OnMessage;
    }
}
