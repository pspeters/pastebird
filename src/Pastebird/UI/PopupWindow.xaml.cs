using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using Pastebird.Core;
using Pastebird.Services;
using static Pastebird.Interop.NativeMethods;

namespace Pastebird.UI;

public enum PopupPlacement
{
    /// <summary>Upper middle of the monitor with the active window (keyboard use).</summary>
    Centered,
    /// <summary>Next to the mouse cursor, e.g. above the tray icon.</summary>
    NearCursor,
}

/// <summary>
/// The Pastebird popup: a search box and the recent items. The window is created once and
/// only hidden/shown afterwards, so it appears instantly.
/// </summary>
public partial class PopupWindow : Window
{
    // The system backdrop API arrived in Windows 11 22H2; the first Windows 11 release (21H2) gets a solid surface.
    private static readonly bool HasSystemBackdrop = Environment.OSVersion.Version.Build >= 22621;

    private readonly ClipboardHistory _history;
    private List<ClipItem> _results = [];
    private IntPtr _hwnd;
    private bool _hiding;
    private bool _allowClose;
    private DateTime _hiddenAt;

    // Placement, in physical pixels of the target monitor.
    private RECT _workArea;
    private int _anchorX, _anchorY;
    private bool _anchorBottom;
    private double _monitorScale = 1;

    public PopupWindow(ClipboardHistory history)
    {
        InitializeComponent();
        _history = history;
        _history.Changed += OnHistoryChanged;

        SourceInitialized += OnSourceInitialized;
        Deactivated += (_, _) => HidePopup();
        SizeChanged += (_, _) => Reposition();
        StateChanged += (_, _) => { if (WindowState != WindowState.Normal) WindowState = WindowState.Normal; };
        PreviewKeyDown += OnPreviewKeyDown;
        SearchBox.TextChanged += (_, _) => Refresh();
        ResultList.PreviewMouseLeftButtonUp += OnResultClicked;
    }

    /// <summary>Raised when the user picks an item. The bool is true when the item should also be pasted.</summary>
    public event Action<ClipItem, bool>? ItemChosen;

    /// <summary>True right after the popup closed; lets a tray click toggle it instead of reopening it.</summary>
    public bool WasJustHidden => (DateTime.UtcNow - _hiddenAt).TotalMilliseconds < 400;

    /// <summary>Creates the native window up front so the first open is fast.</summary>
    public void Prepare() => _hwnd = new WindowInteropHelper(this).EnsureHandle();

    public void ShowPopup(PopupPlacement placement, IntPtr referenceWindow)
    {
        ApplyTheme();
        if (SearchBox.Text.Length > 0) SearchBox.Clear(); else Refresh();

        ComputeAnchor(placement, referenceWindow);
        Reposition();
        Show();
        Activate();
        SearchBox.Focus();
        Keyboard.Focus(SearchBox);
    }

    public void HidePopup()
    {
        if (!IsVisible || _hiding) return;
        _hiding = true;
        _hiddenAt = DateTime.UtcNow;
        Hide();
        _hiding = false;
    }

    public void CloseForShutdown()
    {
        _allowClose = true;
        Close();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true; // Alt+F4 just hides the popup
            HidePopup();
        }
        base.OnClosing(e);
    }

    // ---------------------------------------------------------------- list

    private void Refresh(int preferredIndex = 0)
    {
        _results = FuzzySearch.Filter(_history.Items, SearchBox.Text);
        ResultList.ItemsSource = _results;

        Placeholder.Visibility = SearchBox.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        bool empty = _results.Count == 0;
        ResultList.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        EmptyText.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        EmptyText.Text = Loc.T(_history.Items.Count == 0 ? "popup.empty" : "popup.noResults");

        if (!empty) Select(Math.Clamp(preferredIndex, 0, _results.Count - 1));
    }

    private void OnHistoryChanged()
    {
        if (IsVisible) Refresh(ResultList.SelectedIndex);
    }

    private void Select(int index)
    {
        if (_results.Count == 0) return;
        index = Math.Clamp(index, 0, _results.Count - 1);
        ResultList.SelectedIndex = index;
        ResultList.ScrollIntoView(_results[index]);
    }

    private void TogglePin(ClipItem item)
    {
        _history.TogglePin(item); // refreshes the list through OnHistoryChanged
        Select(_results.IndexOf(item));
    }

    private void Choose(ClipItem item, bool paste)
    {
        HidePopup();
        ItemChosen?.Invoke(item, paste);
    }

    // ---------------------------------------------------------------- input

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        var modifiers = Keyboard.Modifiers;
        switch (e.Key)
        {
            case Key.Escape:
                HidePopup();
                break;
            case Key.Down:
                Select(ResultList.SelectedIndex + 1);
                break;
            case Key.Up:
                Select(ResultList.SelectedIndex - 1);
                break;
            case Key.PageDown:
                Select(ResultList.SelectedIndex + 8);
                break;
            case Key.PageUp:
                Select(ResultList.SelectedIndex - 8);
                break;
            case Key.Enter:
                if (ResultList.SelectedItem is ClipItem item)
                    Choose(item, paste: !modifiers.HasFlag(ModifierKeys.Shift));
                break;
            case Key.Delete when SearchBox.CaretIndex == SearchBox.Text.Length && SearchBox.SelectionLength == 0:
                // Delete only acts on the list when it would do nothing in the search box.
                if (modifiers.HasFlag(ModifierKeys.Control))
                    _history.Clear();
                else if (ResultList.SelectedItem is ClipItem selected)
                    _history.Remove(selected);
                break;
            case Key.P when modifiers == ModifierKeys.Control:
                if (ResultList.SelectedItem is ClipItem toPin)
                    TogglePin(toPin);
                break;
            case Key.Tab:
                break; // keep focus in the search box
            default:
                return;
        }
        e.Handled = true;
    }

    private void OnResultClicked(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is DependencyObject source
            && ItemsControl.ContainerFromElement(ResultList, source) is ListBoxItem { DataContext: ClipItem item })
        {
            if (source is FrameworkElement { Tag: "PinToggle" })
            {
                e.Handled = true;
                TogglePin(item);
                Keyboard.Focus(SearchBox);
            }
            else
            {
                Choose(item, paste: true);
            }
        }
    }

    // ---------------------------------------------------------------- window chrome & theme

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;

        // Hide from Alt+Tab.
        var exStyle = GetWindowLongPtr(_hwnd, GWL_EXSTYLE);
        SetWindowLongPtr(_hwnd, GWL_EXSTYLE, exStyle | WS_EX_TOOLWINDOW);

        // Let DWM render behind the (transparent) WPF content.
        if (HwndSource.FromHwnd(_hwnd)?.CompositionTarget is { } target)
            target.BackgroundColor = Colors.Transparent;

        SetDwmAttribute(_hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND);
        if (HasSystemBackdrop)
            SetDwmAttribute(_hwnd, DWMWA_SYSTEMBACKDROP_TYPE, DWMSBT_TRANSIENTWINDOW);
    }

    private void ApplyTheme()
    {
        bool dark = SystemTheme.IsDark();
        if (_hwnd != IntPtr.Zero)
            SetDwmAttribute(_hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, dark ? 1 : 0);

        SetBrush("Surface", HasSystemBackdrop ? Colors.Transparent : dark ? Rgb(0x2B, 0x2B, 0x2B) : Rgb(0xF9, 0xF9, 0xF9));
        SetBrush("TextPrimary", dark ? Argb(0xFF, 0xFF, 0xFF, 0xFF) : Argb(0xE4, 0, 0, 0));
        SetBrush("TextSecondary", dark ? Argb(0xC5, 0xFF, 0xFF, 0xFF) : Argb(0x9E, 0, 0, 0));
        SetBrush("TextTertiary", dark ? Argb(0x87, 0xFF, 0xFF, 0xFF) : Argb(0x72, 0, 0, 0));
        SetBrush("Divider", dark ? Argb(0x19, 0xFF, 0xFF, 0xFF) : Argb(0x14, 0, 0, 0));
        SetBrush("Hover", dark ? Argb(0x0F, 0xFF, 0xFF, 0xFF) : Argb(0x0A, 0, 0, 0));
        SetBrush("Selected", dark ? Argb(0x15, 0xFF, 0xFF, 0xFF) : Argb(0x0F, 0, 0, 0));
        SetBrush("ScrollThumb", dark ? Argb(0x8B, 0xFF, 0xFF, 0xFF) : Argb(0x72, 0, 0, 0));
        SetBrush("Accent", dark ? SystemColors.AccentColorLight2 : SystemColors.AccentColorDark1);
    }

    private void SetBrush(string key, Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        Resources[key] = brush;
    }

    private static Color Rgb(byte r, byte g, byte b) => Color.FromRgb(r, g, b);
    private static Color Argb(byte a, byte r, byte g, byte b) => Color.FromArgb(a, r, g, b);

    // ---------------------------------------------------------------- placement

    private void ComputeAnchor(PopupPlacement placement, IntPtr referenceWindow)
    {
        GetCursorPos(out var cursor);
        var monitor = placement == PopupPlacement.Centered && referenceWindow != IntPtr.Zero
            ? MonitorFromWindow(referenceWindow, MONITOR_DEFAULTTONEAREST)
            : MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);

        var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(monitor, ref info);
        _workArea = info.rcWork;
        _monitorScale = GetDpiForMonitor(monitor, 0, out uint dpi, out _) == 0 ? dpi / 96.0 : 1;

        int gap = (int)(12 * _monitorScale);
        if (placement == PopupPlacement.Centered)
        {
            _anchorX = (_workArea.Left + _workArea.Right) / 2;
            _anchorY = _workArea.Top + _workArea.Height / 5;
            _anchorBottom = false;
        }
        else
        {
            _anchorX = cursor.X;
            _anchorBottom = cursor.Y > (_workArea.Top + _workArea.Bottom) / 2;
            _anchorY = _anchorBottom
                ? Math.Min(cursor.Y, _workArea.Bottom) - gap
                : Math.Max(cursor.Y, _workArea.Top) + gap;
        }
    }

    /// <summary>Keeps the popup at its anchor (and inside the work area) as its height changes.</summary>
    private void Reposition()
    {
        if (_hwnd == IntPtr.Zero || _workArea.Width == 0) return;

        GetWindowRect(_hwnd, out var rect);
        double windowScale = GetDpiForWindow(_hwnd) / 96.0;
        double rescale = windowScale > 0 ? _monitorScale / windowScale : 1;
        int width = (int)(rect.Width * rescale);
        int height = (int)(rect.Height * rescale);

        int margin = (int)(8 * _monitorScale);
        int x = Math.Clamp(_anchorX - width / 2, _workArea.Left + margin, Math.Max(_workArea.Left + margin, _workArea.Right - width - margin));
        int y = _anchorBottom ? _anchorY - height : _anchorY;
        y = Math.Clamp(y, _workArea.Top + margin, Math.Max(_workArea.Top + margin, _workArea.Bottom - height - margin));

        if (x != rect.Left || y != rect.Top)
            SetWindowPos(_hwnd, IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
}
