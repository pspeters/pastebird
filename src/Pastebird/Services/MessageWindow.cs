using System.Windows.Interop;

namespace Pastebird.Services;

/// <summary>
/// One hidden top-level window that receives the Win32 messages Pastebird depends on:
/// clipboard updates, the global hotkey, tray icon callbacks and system broadcasts.
/// (Top-level rather than message-only, so it also receives WM_SETTINGCHANGE and TaskbarCreated.)
/// </summary>
internal sealed class MessageWindow : IDisposable
{
    public delegate void MessageHandler(int msg, IntPtr wParam, IntPtr lParam, ref bool handled);

    private readonly HwndSource _source;

    public MessageWindow()
    {
        var parameters = new HwndSourceParameters("Pastebird")
        {
            WindowStyle = unchecked((int)0x80000000), // WS_POPUP, never shown
            ExtendedWindowStyle = 0x80,               // WS_EX_TOOLWINDOW
            Width = 0,
            Height = 0,
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    public event MessageHandler? Message;

    public IntPtr Handle => _source.Handle;

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        Message?.Invoke(msg, wParam, lParam, ref handled);
        return IntPtr.Zero;
    }

    public void Dispose() => _source.Dispose();
}
