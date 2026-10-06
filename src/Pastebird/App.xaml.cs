using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Pastebird.Core;
using Pastebird.Services;
using Pastebird.UI;
using static Pastebird.Interop.NativeMethods;

namespace Pastebird;

/// <summary>
/// Pastebird has no main window: the app lives in the tray, watches the clipboard and opens the
/// popup on the global shortcut. This class wires the services together.
/// </summary>
public partial class App : Application
{
    private const string InstanceId = "Pastebird-23DB349F-5518-4A51-BF10-39BBB4178412";

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
    private WhatsNewWindow? _whatsNewWindow;
    private UpdateService? _updates;
    private Action? _notificationAction;
    private DispatcherTimer _saveTimer = null!;
    private readonly DispatcherTimer _expireTimer = new() { Interval = TimeSpan.FromHours(1) };
    private readonly SemaphoreSlim _recognizing = new(1, 1);
    private IntPtr _pasteTarget;
    private bool _hotkeySuspended;

    public AppSettings Settings { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // The UI is tiny, so software rendering is just as fast and avoids loading the
        // Direct3D driver stack, which roughly halves memory use. DWM still draws the backdrop.
        RenderOptions.ProcessRenderMode = RenderMode.SoftwareOnly;

        // Only one Pastebird per user session; starting it again just opens the popup.
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
        Loc.Apply(Settings.Language);

        if (!AppInfo.IsSupportedWindows)
        {
            // The installer and the Store package already block this; it catches a copied Pastebird.exe.
            MessageBox.Show(Loc.T("os.unsupported"), "Pastebird", MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        _history =new ClipboardHistory(_storage.LoadHistory(), Settings.MaxItems);

        // Save shortly after changes instead of on every copy.
        _saveTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _saveTimer.Tick += (_, _) => SaveHistoryNow();
        _history.Changed += () => { _saveTimer.Stop(); _saveTimer.Start(); };

        // Items older than the chosen number of days go: at start and then hourly.
        RemoveExpiredItems();
        _expireTimer.Tick += (_, _) => RemoveExpiredItems();
        _expireTimer.Start();

        _messages = new MessageWindow();
        _messages.Message += OnSystemMessage;
        SystemTheme.EnableDarkMenus(_messages.Handle);

        _monitor = new ClipboardMonitor(_messages);
        _monitor.Captured += OnCaptured;
        _ = RecognizeMissingTextAsync();

        _popup = new PopupWindow(_history, _storage);
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
        _tray.NotificationClicked += () => _notificationAction?.Invoke();

        if (UpdateService.IsSupported)
        {
            _updates = new UpdateService();
            _updates.UpdateFound += OnUpdateFound;
            _tray.UpdateRequested += () => _ = InstallUpdateAsync();
            _updates.Enabled = Settings.CheckForUpdates;
        }

        _ = SyncAutoStartAsync(firstRun);

        // Just updated (also from a version that didn't record LastRunVersion yet)? Offer "What's new".
        var currentVersion = Version.Parse(AppInfo.Version);
        Version.TryParse(Settings.LastRunVersion, out var previousVersion);
        bool updated = !firstRun && (previousVersion is null || previousVersion < currentVersion);
        if (Settings.LastRunVersion != AppInfo.Version)
        {
            Settings.LastRunVersion = AppInfo.Version;
            _storage.SaveSettings(Settings);
        }

        if (updated)
        {
            ShowNotification(Loc.T("notify.updated.title", AppInfo.Version), Loc.T("notify.updated.text"),
                () => ShowWhatsNew(previousVersion, afterUpdate: true));
        }
        if (firstRun)
        {
            _storage.SaveSettings(Settings);
            ShowNotification(Loc.T("notify.running.title"), Loc.T("notify.running.text", Settings.Hotkey));
        }
        if (!hotkeyRegistered)
        {
            ShowNotification(Loc.T("notify.hotkey.title"), Loc.T("notify.hotkey.text", Settings.Hotkey));
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

    private void OnCaptured(ClipItem copied, ClipData? data)
    {
        var item = _history.Add(copied);
        _storage.SaveData(item, data);
        if (item.Kind == ClipKind.Image && item.ImageText is null)
            _ = RecognizeTextAsync(item);
    }

    /// <summary>Reads the text in an image in the background, one image at a time, so it can be found by searching.</summary>
    private async Task RecognizeTextAsync(ClipItem item)
    {
        await _recognizing.WaitAsync();
        try
        {
            if (item.ImageText is not null || !_history.Items.Contains(item)) return;
            var text = await Task.Run(async () => _storage.LoadData(item)?.Png is { } png ? await TextRecognition.RecognizeAsync(png) : null);
            if (text is not null)
                _history.SetImageText(item, text);
        }
        catch (Exception ex)
        {
            LocalStorage.Log(ex);
        }
        finally
        {
            _recognizing.Release();
        }
    }

    /// <summary>Recognizes the text in images that don't have it yet (copied with an older version, or before a language was installed).</summary>
    private async Task RecognizeMissingTextAsync()
    {
        await Task.Delay(TimeSpan.FromSeconds(30)); // not while Windows is still starting
        foreach (var item in _history.Items.Where(i => i.Kind == ClipKind.Image && i.ImageText is null).ToList())
            await RecognizeTextAsync(item);
    }

    private void OnItemChosen(ClipItem item, bool paste, bool keepFormatting)
    {
        try
        {
            _monitor!.SetClipboard(item, _storage.LoadData(item), keepFormatting);
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

    public void SetLanguage(AppLanguage language)
    {
        Settings.Language = language;
        _storage.SaveSettings(Settings);
        Loc.Apply(language);
    }

    public void SetMaxItems(int maxItems)
    {
        Settings.MaxItems = maxItems;
        _storage.SaveSettings(Settings);
        _history.MaxItems = maxItems;
    }

    public void SetKeepDays(int days)
    {
        Settings.KeepDays = days;
        _storage.SaveSettings(Settings);
        RemoveExpiredItems();
    }

    private void RemoveExpiredItems()
    {
        if (Settings.KeepDays > 0)
            _history.RemoveCopiedBefore(DateTime.UtcNow.AddDays(-Settings.KeepDays));
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
        if (!_history.HasUnpinnedItems) return;

        var question = Loc.T("clear.confirm");
        var answer = confirmOwner is null
            ? MessageBox.Show(question, "Pastebird", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No)
            : MessageBox.Show(confirmOwner, question, "Pastebird", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (answer == MessageBoxResult.Yes)
            _history.Clear();
    }

    // ---------------------------------------------------------------- what's new

    /// <summary>Shows the changelog entries since <paramref name="since"/> (all entries when null or nothing is newer).</summary>
    public void ShowWhatsNew(Version? since = null, bool afterUpdate = false)
    {
        _whatsNewWindow?.Close();
        var releases = Changelog.Between(since, Version.Parse(AppInfo.Version));
        if (releases.Count == 0)
            releases = Changelog.Load();
        _whatsNewWindow = new WhatsNewWindow(releases, afterUpdate);
        _whatsNewWindow.Closed += (_, _) => _whatsNewWindow = null;
        _whatsNewWindow.Show();
        _whatsNewWindow.Activate();
    }

    // ---------------------------------------------------------------- updates

    public bool UpdatesSupported => _updates is not null;

    public UpdateInfo? AvailableUpdate => _updates?.Available;

    /// <summary>Raised when a newer version is found, so an open Settings window can show it.</summary>
    public event Action? UpdateStateChanged;

    public void SetCheckForUpdates(bool enabled)
    {
        Settings.CheckForUpdates = enabled;
        _storage.SaveSettings(Settings);
        if (_updates is not null) _updates.Enabled = enabled;
    }

    /// <summary>Checks right away (from Settings). Returns false when GitHub couldn't be reached.</summary>
    public Task<bool> CheckForUpdatesAsync() => _updates?.CheckAsync() ?? Task.FromResult(false);

    private void OnUpdateFound(UpdateInfo update)
    {
        _tray!.UpdateVersion = update.Version.ToString(3);
        ShowNotification(Loc.T("notify.update.title"), Loc.T("notify.update.text", update.Version.ToString(3)), () => _ = InstallUpdateAsync());
        UpdateStateChanged?.Invoke();
    }

    /// <summary>Downloads and runs the new installer, then exits so it can replace Pastebird; the installer restarts it.</summary>
    public async Task InstallUpdateAsync()
    {
        if (_updates?.Available is not { } update) return;

        ShowNotification(Loc.T("notify.updating.title"), Loc.T("notify.updating.text"));
        if (await _updates.DownloadAndStartInstallerAsync(update))
        {
            ExitApp();
            return;
        }
        ShowNotification(Loc.T("notify.updatefailed.title"), Loc.T("notify.updatefailed.text"), () => OpenUrl(AppInfo.ReleasesUrl));
    }

    /// <summary>Shows a tray notification; <paramref name="onClick"/> runs when the user clicks it.</summary>
    private void ShowNotification(string title, string text, Action? onClick = null)
    {
        _notificationAction = onClick;
        _tray!.ShowNotification(title, text);
    }

    public static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception ex) { LocalStorage.Log(ex); }
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
        _storage.SaveHistory(_history.Items, _history.RecentlyRemoved);
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
        _updates?.Dispose();
        _monitor?.Dispose();
        _tray?.Dispose();
        _messages?.Dispose();
        _singleInstance?.ReleaseMutex();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }
}
