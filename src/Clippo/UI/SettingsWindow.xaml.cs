using System.Windows;
using System.Windows.Input;
using Clippo.Core;

namespace Clippo.UI;

/// <summary>The small settings window. Every change applies and saves immediately.</summary>
public partial class SettingsWindow : Window
{
    private const string DefaultHint = "Klik en kies een nieuwe combinatie.";
    private const string DefaultAutoStartHint = "Clippo start automatisch op de achtergrond na het aanmelden.";

    private readonly App _app;

    public SettingsWindow(App app)
    {
        InitializeComponent();
        _app = app;
        var settings = app.Settings;

        AutoStartBox.IsChecked = settings.StartWithWindows;
        AutoPasteBox.IsChecked = settings.PasteAutomatically;
        HotkeyBox.Text = settings.Hotkey.ToString();
        HistorySizeBox.ItemsSource = AppSettings.HistorySizes.Select(n => $"{n} items").ToList();
        HistorySizeBox.SelectedIndex = Array.IndexOf(AppSettings.HistorySizes, settings.MaxItems);
        FooterText.Text = $"Clippo {typeof(App).Assembly.GetName().Version?.ToString(3)} · Alle gegevens blijven lokaal op deze pc.";

        AutoStartBox.Click += async (_, _) =>
        {
            bool wanted = AutoStartBox.IsChecked == true;
            bool actual = await _app.SetAutoStartAsync(wanted);
            AutoStartBox.IsChecked = actual;
            AutoStartHint.Text = wanted && !actual
                ? "Windows staat dit niet toe. Zet Clippo aan via Taakbeheer → Opstart-apps."
                : DefaultAutoStartHint;
        };
        AutoPasteBox.Click += (_, _) => _app.SetAutoPaste(AutoPasteBox.IsChecked == true);
        HistorySizeBox.SelectionChanged += (_, _) =>
        {
            if (HistorySizeBox.SelectedIndex >= 0)
                _app.SetMaxItems(AppSettings.HistorySizes[HistorySizeBox.SelectedIndex]);
        };
        ClearButton.Click += (_, _) => _app.ClearHistory(confirmOwner: this);

        HotkeyBox.GotKeyboardFocus += (_, _) =>
        {
            _app.SuspendHotkey(); // otherwise the current shortcut would open the popup instead
            HotkeyBox.Text = "Druk op toetsen…";
        };
        HotkeyBox.LostKeyboardFocus += (_, _) =>
        {
            _app.ResumeHotkey();
            HotkeyBox.Text = _app.Settings.Hotkey.ToString();
        };
        HotkeyBox.PreviewKeyDown += OnHotkeyKeyDown;
        KeyDown += (_, e) => { if (e.Key == Key.Escape) Close(); };
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
        {
            HotkeyHint.Text = "Gebruik minstens Ctrl, Alt of Win in de combinatie.";
            return;
        }

        if (_app.TrySetHotkey(hotkey))
        {
            HotkeyHint.Text = DefaultHint;
            Focus();
        }
        else
        {
            HotkeyHint.Text = $"{hotkey} is al in gebruik door een ander programma.";
        }
    }
}
