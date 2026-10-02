using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using Clippo.Core;

namespace Clippo.UI;

/// <summary>The small settings window. Every change applies and saves immediately.</summary>
public partial class SettingsWindow : Window
{
    private readonly App _app;
    private string _autoStartHintKey = "settings.autostart.desc";
    private string _hotkeyHint = "";
    private bool _updatingLists;

    public SettingsWindow(App app)
    {
        InitializeComponent();
        _app = app;
        var settings = app.Settings;
        MaxHeight = SystemParameters.WorkArea.Height - 40;

        AutoStartBox.IsChecked = settings.StartWithWindows;
        AutoPasteBox.IsChecked = settings.PasteAutomatically;
        HotkeyBox.Text = settings.Hotkey.ToString();
        AppIcon.Source = LoadLargestIconFrame();
        UpdateTexts();

        Loc.Instance.PropertyChanged += OnLanguageChanged;
        Closed += (_, _) => Loc.Instance.PropertyChanged -= OnLanguageChanged;

        AutoStartBox.Click += async (_, _) =>
        {
            bool wanted = AutoStartBox.IsChecked == true;
            bool actual = await _app.SetAutoStartAsync(wanted);
            AutoStartBox.IsChecked = actual;
            _autoStartHintKey = wanted && !actual ? "settings.autostart.denied" : "settings.autostart.desc";
            UpdateTexts();
        };
        AutoPasteBox.Click += (_, _) => _app.SetAutoPaste(AutoPasteBox.IsChecked == true);
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

        _updatingLists = true;
        HistorySizeBox.ItemsSource = AppSettings.HistorySizes.Select(n => Loc.T("settings.history.items", n)).ToList();
        HistorySizeBox.SelectedIndex = Array.IndexOf(AppSettings.HistorySizes, _app.Settings.MaxItems);
        LanguageBox.ItemsSource = new[] { Loc.T("settings.language.system"), "English", "Nederlands" };
        LanguageBox.SelectedIndex = (int)_app.Settings.Language;
        _updatingLists = false;
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
        var decoder = BitmapDecoder.Create(new Uri("pack://application:,,,/Clippo;component/Assets/clippo.ico"),
            BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        return decoder.Frames.OrderByDescending(f => f.PixelWidth).First();
    }

    private static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception ex) { LocalStorage.Log(ex); }
    }
}
