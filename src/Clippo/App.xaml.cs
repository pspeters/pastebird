using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Clippo.Core;
using Clippo.Services;
using Clippo.UI;
using static Clippo.Interop.NativeMethods;

namespace Clippo;

/// <summary>
/// Clippo has no main window: the app lives in the tray, watches the clipboard and opens the
/// popup on the global shortcut. This class wires the services together.
/// </summary>
public partial class App : Application
{
    private const string InstanceId = "Clippo-6A0F3C2E-7D51-4B8E-9C3A-21F4E8B0D7A9";

    private Mutex? _singleInstance;
    private EventWaitHandle? _showSignal;
    private RegisteredWaitHandle? _showSignalWait;

    private LocalStorage _storage = null!;
    private ClipboardHistory _history = null!;
    private MessageWindow? _messages;
    private ClipboardMonitor? _monitor;
    private GlobalHotkeyService? _hotkey;
    private TrayIconService? _tray;
    private PopupWindow? _popup;
    private SettingsWindow? _settingsWindow;
    private DispatcherTimer _saveTimer = null!;
    private IntPtr _pasteTarget;
    private bool _hotkeySuspended;

    public AppSettings Settings { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // The UI is tiny, so software rendering is just as fast and avoids loading the
        // Direct3D driver stack, which roughly halves memory use. DWM still draws the backdrop.
        RenderOptions.ProcessRenderMode = RenderMode.SoftwareOnly;

        // Only one Clippo per user session; starting it again just opens the popup.
        _singleInstance = new Mutex(true, $@"Local\{InstanceId}", out bool isFirstInstance);
        if (!isFirstInstance)
        {
            AllowSetForegroundWindow(ASFW_ANY);
            if (EventWaitHandle.TryOpenExisting($@"Local\{InstanceId}-Show", out var signal))
                using (signal) signal.Set();
            _singleInstance.Dispose();
            _singleInstance = null;
            Shutdown();
            return;
        }

        DispatcherUnhandledException += (_, args) =>
        {
            LocalStorage.Log(args.Exception);
            args.Handled = true; // stay alive in the tray
        };

        _storage = new LocalStorage();
        bool firstRun = !_storage.SettingsExist;
        Settings = _storage.LoadSettings();
        _history = new ClipboardHistory(_storage.LoadHistory(), Settings.MaxItems);

        // Save shortly after changes instead of on every copy.
        _saveTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _saveTimer.Tick += (_, _) => SaveHistoryNow();
        _history.Changed += () => { _saveTimer.Stop(); _saveTimer.Start(); };

        _messages = new MessageWindow();
        _messages.Message += OnSystemMessage;
        SystemTheme.EnableDarkMenus(_messages.Handle);

        _monitor = new ClipboardMonitor(_messages);
        _monitor.Captured += _history.Add;

        _popup = new PopupWindow(_history);
        _popup.ItemChosen += OnItemChosen;
        _popup.Prepare();

        _hotkey = new GlobalHotkeyService(_messages);
        _hotkey.Pressed += OnHotkeyPressed;
        bool hotkeyRegistered = _hotkey.Register(Settings.Hotkey);

        _tray = new TrayIconService(_messages);
        _tray.OpenRequested += OnTrayOpen;
        _tray.ClearRequested += () => ClearHistory(confirmOwner: null);
        _tray.SettingsRequested += ShowSettings;
        _tray.ExitRequested += ExitApp;

        _ = SyncAutoStartAsync(firstRun);

        if (firstRun)
        {
            _storage.SaveSettings(Settings);
            _tray.ShowNotification("Clippo draait op de achtergrond",
                $"Druk op {Settings.Hotkey} om je klembordgeschiedenis te openen.");
        }
        if (!hotkeyRegistered)
        {
            _tray.ShowNotification("Sneltoets niet beschikbaar",
                $"{Settings.Hotkey} wordt al door een ander programma gebruikt. Kies een andere sneltoets via Instellingen.");
        }

        _showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, $@"Local\{InstanceId}-Show");
        _showSignalWait = ThreadPool.RegisterWaitForSingleObject(_showSignal,
            (_, _) => Dispatcher.BeginInvoke(() => OpenPopup(PopupPlacement.Centered, allowPaste: false)),
            null, Timeout.Infinite, executeOnlyOnce: false);
    }

    // ---------------------------------------------------------------- popup

    private void OnHotkeyPressed()
    {
        if (_popup!.IsVisible)
            _popup.HidePopup(); // the shortcut toggles
        else
            OpenPopup(PopupPlacement.Centered, allowPaste: true);
    }

    private void OnTrayOpen()
    {
        // Clicking the icon while the popup is open closes it (the click itself already hid it).
        if (_popup!.WasJustHidden) return;
        OpenPopup(PopupPlacement.NearCursor, allowPaste: false);
    }

    private void OpenPopup(PopupPlacement placement, bool allowPaste)
    {
        var foreground = PasteService.CaptureTarget();
        _pasteTarget = allowPaste ? foreground : IntPtr.Zero;
        _popup!.ShowPopup(placement, foreground);
    }

    private void OnItemChosen(ClipItem item, bool paste)
    {
        try
        {
            _monitor!.SetClipboard(item);
        }
        catch (Exception ex) when (ex is ExternalException or InvalidOperationException)
        {
            LocalStorage.Log(ex);
            return; // clipboard locked by another app; nothing to paste
        }

        _history.Promote(item);

        if (paste && Settings.PasteAutomatically && _pasteTarget != IntPtr.Zero)
            _ = PasteService.PasteAsync(_pasteTarget);
        _pasteTarget = IntPtr.Zero;
    }

    // ---------------------------------------------------------------- settings (used by SettingsWindow)

    private void ShowSettings()
    {
        if (_settingsWindow is null)
        {
            _settingsWindow = new SettingsWindow(this);
            _settingsWindow.Closed += (_, _) => { _settingsWindow = null; ResumeHotkey(); };
        }
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    /// <summary>Applies the autostart setting and returns the state that actually took effect.</summary>
    public async Task<bool> SetAutoStartAsync(bool enabled)
    {
        bool actual = enabled;
        try { actual = await AutoStart.ApplyAsync(enabled); }
        catch (Exception ex) { LocalStorage.Log(ex); }

        Settings.StartWithWindows = actual;
        _storage.SaveSettings(Settings);
        return actual;
    }

    private async Task SyncAutoStartAsync(bool firstRun)
    {
        try
        {
            // Store version: the user can switch the startup task off in Task Manager, so follow its state.
            if (AutoStart.IsPackaged && !firstRun && await AutoStart.GetPackagedStateAsync() is bool packagedState)
            {
                if (packagedState != Settings.StartWithWindows)
                {
                    Settings.StartWithWindows = packagedState;
                    _storage.SaveSettings(Settings);
                }
                return;
            }
            await AutoStart.ApplyAsync(Settings.StartWithWindows);
        }
        catch (Exception ex)
        {
            LocalStorage.Log(ex);
        }
    }

    public void SetAutoPaste(bool enabled)
    {
        Settings.PasteAutomatically = enabled;
        _storage.SaveSettings(Settings);
    }

    public void SetMaxItems(int maxItems)
    {
        Settings.MaxItems = maxItems;
        _storage.SaveSettings(Settings);
        _history.MaxItems = maxItems;
    }

    /// <summary>Checks that the shortcut is free and stores it. It becomes active once editing ends.</summary>
    public bool TrySetHotkey(Hotkey hotkey)
    {
        if (!_hotkey!.Register(hotkey))
            return false;
        if (_hotkeySuspended)
            _hotkey.Unregister();

        Settings.Hotkey = hotkey;
        _storage.SaveSettings(Settings);
        return true;
    }

    public void SuspendHotkey()
    {
        _hotkeySuspended = true;
        _hotkey?.Unregister();
    }

    public void ResumeHotkey()
    {
        if (!_hotkeySuspended) return;
        _hotkeySuspended = false;
        _hotkey?.Register(Settings.Hotkey);
    }

    public void ClearHistory(Window? confirmOwner)
    {
        if (_history.Items.Count == 0) return;

        const string question = "Wil je de volledige clipboardgeschiedenis wissen?";
        var answer = confirmOwner is null
            ? MessageBox.Show(question, "Clippo", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No)
            : MessageBox.Show(confirmOwner, question, "Clippo", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (answer == MessageBoxResult.Yes)
            _history.Clear();
    }

    // ---------------------------------------------------------------- lifetime

    private void OnSystemMessage(int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_SETTINGCHANGE && lParam != IntPtr.Zero && Marshal.PtrToStringUni(lParam) == "ImmersiveColorSet")
            SystemTheme.RefreshMenus();
    }

    private void SaveHistoryNow()
    {
        _saveTimer.Stop();
        _storage.SaveHistory(_history.Items);
    }

    private void ExitApp()
    {
        _popup?.CloseForShutdown();
        Shutdown();
    }

    protected override void OnSessionEnding(SessionEndingCancelEventArgs e)
    {
        if (_history is not null) SaveHistoryNow();
        base.OnSessionEnding(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (_history is not null) SaveHistoryNow();

        _showSignalWait?.Unregister(null);
        _showSignal?.Dispose();
        _hotkey?.Dispose();
        _monitor?.Dispose();
        _tray?.Dispose();
        _messages?.Dispose();
        _singleInstance?.ReleaseMutex();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }
}
