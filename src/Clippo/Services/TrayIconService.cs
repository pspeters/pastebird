using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using Clippo.Core;
using static Clippo.Interop.NativeMethods;

namespace Clippo.Services;

/// <summary>
/// The notification-area icon (Shell_NotifyIcon) with a native Windows context menu,
/// so the menu looks and behaves exactly like other tray menus (incl. dark mode).
/// </summary>
internal sealed class TrayIconService : IDisposable
{
    private const int CallbackMessage = WM_APP + 1;
    private const int CmdOpen = 1, CmdClear = 2, CmdSettings = 3, CmdExit = 4;

    private readonly MessageWindow _window;
    private readonly int _taskbarCreatedMessage = RegisterWindowMessage("TaskbarCreated");
    private readonly IntPtr _icon;

    public TrayIconService(MessageWindow window)
    {
        _window = window;
        _icon = LoadTrayIcon();
        _window.Message += OnMessage;
        AddIcon();
    }

    public event Action? OpenRequested;
    public event Action? ClearRequested;
    public event Action? SettingsRequested;
    public event Action? ExitRequested;

    public void ShowNotification(string title, string text)
    {
        var data = NewData();
        data.uFlags = NIF_INFO;
        data.szInfoTitle = title;
        data.szInfo = text;
        Shell_NotifyIcon(NIM_MODIFY, ref data);
    }

    private void AddIcon()
    {
        var data = NewData();
        data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
        data.uCallbackMessage = CallbackMessage;
        data.hIcon = _icon;
        data.szTip = "Clippo";
        Shell_NotifyIcon(NIM_ADD, ref data);

        data.uVersion = NOTIFYICON_VERSION_4;
        Shell_NotifyIcon(NIM_SETVERSION, ref data);
    }

    private NOTIFYICONDATA NewData() => new()
    {
        cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
        hWnd = _window.Handle,
        uID = 1,
        szTip = "",
        szInfo = "",
        szInfoTitle = "",
    };

    private void OnMessage(int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == _taskbarCreatedMessage)
        {
            AddIcon(); // Explorer restarted
            return;
        }
        if (msg != CallbackMessage) return;

        handled = true;
        switch ((int)(lParam.ToInt64() & 0xFFFF))
        {
            case NIN_SELECT:
            case NIN_KEYSELECT:
                OpenRequested?.Invoke();
                break;
            case WM_CONTEXTMENU:
                long anchor = wParam.ToInt64();
                ShowMenu((short)(anchor & 0xFFFF), (short)((anchor >> 16) & 0xFFFF));
                break;
        }
    }

    private void ShowMenu(int x, int y)
    {
        var menu = CreatePopupMenu();
        try
        {
            AppendMenu(menu, MF_STRING, CmdOpen, Loc.T("tray.open"));
            AppendMenu(menu, MF_STRING, CmdClear, Loc.T("tray.clear"));
            AppendMenu(menu, MF_STRING, CmdSettings, Loc.T("tray.settings"));
            AppendMenu(menu, MF_SEPARATOR, 0, null);
            AppendMenu(menu, MF_STRING, CmdExit, Loc.T("tray.exit"));
            SetMenuDefaultItem(menu, CmdOpen, 0);

            // Required so the menu closes when the user clicks elsewhere.
            SetForegroundWindow(_window.Handle);
            int command = TrackPopupMenuEx(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, x, y, _window.Handle, IntPtr.Zero);
            PostMessage(_window.Handle, WM_NULL, IntPtr.Zero, IntPtr.Zero);

            switch (command)
            {
                case CmdOpen: OpenRequested?.Invoke(); break;
                case CmdClear: ClearRequested?.Invoke(); break;
                case CmdSettings: SettingsRequested?.Invoke(); break;
                case CmdExit: ExitRequested?.Invoke(); break;
            }
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    /// <summary>Picks the best small-icon size from the embedded .ico for the current DPI.</summary>
    private static IntPtr LoadTrayIcon()
    {
        int size = GetSystemMetricsForDpi(SM_CXSMICON, GetDpiForSystem());
        var resource = Application.GetResourceStream(new Uri("pack://application:,,,/Clippo;component/Assets/clippo.ico"));
        using var stream = new MemoryStream();
        resource.Stream.CopyTo(stream);
        var ico = stream.ToArray();

        int count = BitConverter.ToUInt16(ico, 4);
        int best = -1, bestSize = 0;
        for (int i = 0; i < count; i++)
        {
            int entrySize = ico[6 + i * 16] == 0 ? 256 : ico[6 + i * 16];
            bool better = best < 0
                || (entrySize >= size && (bestSize < size || entrySize < bestSize))
                || (bestSize < size && entrySize > bestSize);
            if (better) { best = i; bestSize = entrySize; }
        }

        int length = BitConverter.ToInt32(ico, 6 + best * 16 + 8);
        int offset = BitConverter.ToInt32(ico, 6 + best * 16 + 12);
        return CreateIconFromResourceEx(ico[offset..(offset + length)], (uint)length, true, 0x00030000, size, size, 0);
    }

    public void Dispose()
    {
        var data = NewData();
        Shell_NotifyIcon(NIM_DELETE, ref data);
        _window.Message -= OnMessage;
        DestroyIcon(_icon);
    }
}
