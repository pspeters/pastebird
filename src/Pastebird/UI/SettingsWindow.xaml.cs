using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using Pastebird.Core;

namespace Pastebird.UI;

/// <summary>The small settings window. Every change applies and saves immediately.</summary>
public partial class SettingsWindow : Window
{
    private readonly App _app;
    private string _autoStartHintKey = "settings.autostart.desc";
    private string _hotkeyHint = "";
    private bool _updatingLists;
    private string _updateStatusKey = "";

    public SettingsWindow(App app)
    {
        InitializeComponent();
        _app = app;
        var settings = app.Settings;
        MaxHeight = SystemParameters.WorkArea.Height - 40;

        AutoStartBox.IsChecked = settings.StartWithWindows;
        AutoPasteBox.IsChecked = settings.PasteAutomatically;
        UpdatesBox.IsChecked = settings.CheckForUpdates;
        if (!app.UpdatesSupported)
            UpdatesCard.Visibility = Visibility.Collapsed; // the Microsoft Store keeps the Store version up to date
        HotkeyBox.Text = settings.Hotkey.ToString();
        AppIcon.Source = LoadLargestIconFrame();
        UpdateTexts();

        Loc.Instance.PropertyChanged += OnLanguageChanged;
        _app.UpdateStateChanged += UpdateTexts;
        Closed += (_, _) =>
        {
            Loc.Instance.PropertyChanged -= OnLanguageChanged;
            _app.UpdateStateChanged -= UpdateTexts;
        };

        AutoStartBox.Click += async (_, _) =>
        {
            bool wanted = AutoStartBox.IsChecked == true;
            bool actual = await _app.SetAutoStartAsync(wanted);
            AutoStartBox.IsChecked = actual;
            _autoStartHintKey = wanted && !actual ? "settings.autostart.denied" : "settings.autostart.desc";
            UpdateTexts();
        };
        AutoPasteBox.Click += (_, _) => _app.SetAutoPaste(AutoPasteBox.IsChecked == true);
        UpdatesBox.Click += (_, _) => _app.SetCheckForUpdates(UpdatesBox.IsChecked == true);
        UpdateButton.Click += OnUpdateButtonClick;
        HistorySizeBox.SelectionChanged += (_, _) =>
        {
            if (!_updatingLists && HistorySizeBox.SelectedIndex >= 0)
                _app.SetMaxItems(AppSettings.HistorySizes[HistorySizeBox.SelectedIndex]);
        };
        LanguageBox.SelectionChanged += (_, _) =>
        {
            if (!_updatingLists && LanguageBox.SelectedIndex >= 0)
                _app.SetLanguage((AppLanguage)LanguageBox.SelectedIndex);
        };
        ClearButton.Click += (_, _) => _app.ClearHistory(confirmOwner: this);
        GitHubButton.Click += (_, _) => OpenUrl(AppInfo.GitHubUrl);
        DonateButton.Click += (_, _) => OpenUrl(AppInfo.DonateUrl);

        HotkeyBox.GotKeyboardFocus += (_, _) =>
        {
            _app.SuspendHotkey(); // otherwise the current shortcut would open the popup instead
            HotkeyBox.Text = Loc.T("settings.hotkey.press");
        };
        HotkeyBox.LostKeyboardFocus += (_, _) =>
        {
            _app.ResumeHotkey();
            HotkeyBox.Text = _app.Settings.Hotkey.ToString();
        };
        HotkeyBox.PreviewKeyDown += OnHotkeyKeyDown;
        KeyDown += (_, e) => { if (e.Key == Key.Escape) Close(); };
    }

    private void OnLanguageChanged(object? sender, PropertyChangedEventArgs e)
    {
        UpdateTexts();
        if (!HotkeyBox.IsKeyboardFocused)
            HotkeyBox.Text = _app.Settings.Hotkey.ToString(); // key names like "Space" are translated too
    }

    /// <summary>Texts that are built in code (everything else binds to <see cref="Loc"/> in XAML).</summary>
    private void UpdateTexts()
    {
        AutoStartHint.Text = Loc.T(_autoStartHintKey);
        HotkeyHint.Text = _hotkeyHint.Length > 0 ? _hotkeyHint : Loc.T("settings.hotkey.desc");
        VersionText.Text = $"{Loc.T("about.version", AppInfo.Version)} · {Loc.T("about.license")}";

        var update = _app.AvailableUpdate;
        UpdateStatus.Text = update is not null
            ? Loc.T("settings.updates.available", update.Version.ToString(3))
            : _updateStatusKey.Length > 0 ? Loc.T(_updateStatusKey) : Loc.T("about.version", AppInfo.Version);
        UpdateButton.Content = Loc.T(update is not null ? "settings.updates.install" : "settings.updates.check");

        _updatingLists = true;
        HistorySizeBox.ItemsSource = AppSettings.HistorySizes.Select(n => Loc.T("settings.history.items", n)).ToList();
        HistorySizeBox.SelectedIndex = Array.IndexOf(AppSettings.HistorySizes, _app.Settings.MaxItems);
        LanguageBox.ItemsSource = new[] { Loc.T("settings.language.system"), "English", "Nederlands" };
        LanguageBox.SelectedIndex = (int)_app.Settings.Language;
        _updatingLists = false;
    }

    private async void OnUpdateButtonClick(object sender, RoutedEventArgs e)
    {
        UpdateButton.IsEnabled = false;
        try
        {
            if (_app.AvailableUpdate is not null)
            {
                _updateStatusKey = "settings.updates.installing";
                UpdateStatus.Text = Loc.T(_updateStatusKey);
                await _app.InstallUpdateAsync(); // exits Pastebird when the installer starts
                _updateStatusKey = "settings.updates.failed";
            }
            else
            {
                UpdateStatus.Text = Loc.T("settings.updates.checking");
                bool reached = await _app.CheckForUpdatesAsync();
                _updateStatusKey = !reached ? "settings.updates.offline" : _app.AvailableUpdate is null ? "settings.updates.current" : "";
            }
        }
        finally
        {
            UpdateButton.IsEnabled = true;
            UpdateTexts();
        }
    }

    private void OnHotkeyKeyDown(object sender, KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Tab) return; // allow keyboard navigation away
        e.Handled = true;

        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift
            or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
            return;

        if (key == Key.Escape && Keyboard.Modifiers == ModifierKeys.None)
        {
            Focus(); // cancel: move focus off the box
            return;
        }

        var hotkey = Hotkey.FromWpf(Keyboard.Modifiers, key);
        if (!hotkey.IsValid)
            _hotkeyHint = Loc.T("settings.hotkey.modifier");
        else if (_app.TrySetHotkey(hotkey))
        {
            _hotkeyHint = "";
            Focus();
        }
        else
            _hotkeyHint = Loc.T("settings.hotkey.taken", hotkey);

        UpdateTexts();
    }

    private static BitmapSource LoadLargestIconFrame()
    {
        var decoder = BitmapDecoder.Create(new Uri("pack://application:,,,/Pastebird;component/Assets/pastebird.ico"),
            BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        return decoder.Frames.OrderByDescending(f => f.PixelWidth).First();
    }

    private static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception ex) { LocalStorage.Log(ex); }
    }
}
