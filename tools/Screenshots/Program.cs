using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using Pastebird.Core;
using Pastebird.UI;

// Renders screenshots of the real popup with sample data, so no real clipboard history ends up in them.
//   dotnet run --project tools/Screenshots -- <output folder> [en|nl]
// The popup is shown off-screen and never activated; the Windows 11 backdrop is drawn here instead.

var output = Path.GetFullPath(args.Length > 0 ? args[0] : "screenshots");
var language = args.Length > 1 && args[1] == "nl" ? AppLanguage.Dutch : AppLanguage.English;
Directory.CreateDirectory(output);

var thread = new Thread(() =>
{
    _ = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
    Loc.Apply(language);
    var shots = new Screenshots(output, language == AppLanguage.Dutch);
    shots.RenderAll();
});
thread.SetApartmentState(ApartmentState.STA);
thread.Start();
thread.Join();

internal sealed class Screenshots(string output, bool dutch)
{
    // Canvas in device-independent pixels, rendered at 2x: 1920 × 1080 PNGs (Microsoft Store: 16:9, at least 1366 × 768).
    private const double Width = 960, Height = 540, Scale = 2;
    private static readonly BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;

    private string T(string en, string nl) => dutch ? nl : en;

    public void RenderAll()
    {
        Shot("1-history", dark: false, search: "", select: 0, preview: false,
            T("Your clipboard,\nwith a memory.", "Je klembord,\nmet geheugen."),
            T("Press Ctrl+Shift+V to see everything you copied: text, links, files and screenshots.",
              "Druk op Ctrl+Shift+V en zie alles wat je kopieerde: tekst, links, bestanden en screenshots."));
        Shot("2-search", dark: false, search: "proj", select: 0, preview: false,
            T("Find it in a\nfew keystrokes.", "Gevonden in een\npaar toetsaanslagen."),
            T("Fuzzy search: type \"proj\" and your project files show up. Press Enter to paste.",
              "Slim zoeken: typ \"proj\" en je projectbestanden verschijnen. Enter plakt het."));
        Shot("3-preview", dark: false, search: "", select: 6, preview: true,
            T("See the\nwhole item.", "Bekijk het\nhele item."),
            T("Press Tab to preview long or multi-line text, and see when you copied it.",
              "Druk op Tab voor de volledige inhoud van lange tekst, en zie wanneer je het kopieerde."));
        Shot("4-dark", dark: true, search: "", select: 4, preview: false,
            T("Pin what you\nuse often.", "Pin wat je\nvaak gebruikt."),
            T("Pinned items stay at the top. Light and dark mode, just like Windows 11. Everything stays on your pc.",
              "Vastgepinde items blijven bovenaan. Licht en donker, net als Windows 11. Alles blijft op je pc."));
    }

    private void Shot(string name, bool dark, string search, int select, bool preview, string title, string text)
    {
        var popup = RenderPopup(dark, search, select, preview, out double popupWidth, out double popupHeight);

        var root = new Grid { Width = Width, Height = Height, Background = Backdrop(dark) };
        var ink = dark ? Color.FromRgb(0xE8, 0xEE, 0xF8) : Color.FromRgb(0x0F, 0x17, 0x2A);
        var muted = dark ? Color.FromRgb(0xA9, 0xB6, 0xCC) : Color.FromRgb(0x47, 0x55, 0x69);

        var caption = new StackPanel { Width = 330, Margin = new Thickness(48, 0, 0, 0), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
        caption.Children.Add(new Image { Source = Logo(), Width = 52, Height = 52, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 18) });
        caption.Children.Add(new TextBlock { Text = title, FontFamily = new FontFamily("Segoe UI Variable Display, Segoe UI"), FontSize = 38, FontWeight = FontWeights.Bold, LineHeight = 44, Foreground = new SolidColorBrush(ink) });
        caption.Children.Add(new TextBlock { Text = text, FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"), FontSize = 16, LineHeight = 24, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 16, 0, 0), Foreground = new SolidColorBrush(muted) });
        root.Children.Add(caption);

        // The popup on a Windows 11 style surface: rounded corners, thin border, soft shadow.
        var surface = new Border
        {
            Width = popupWidth,
            Height = popupHeight,
            CornerRadius = new CornerRadius(8),
            Background = new SolidColorBrush(dark ? Color.FromArgb(0xF0, 0x2C, 0x2C, 0x2C) : Color.FromArgb(0xF2, 0xF9, 0xF9, 0xF9)),
            BorderBrush = new SolidColorBrush(dark ? Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x1A, 0, 0, 0)),
            BorderThickness = new Thickness(1),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 48, 0),
            Effect = new DropShadowEffect { BlurRadius = 48, ShadowDepth = 12, Direction = 270, Opacity = dark ? 0.55 : 0.22, Color = Colors.Black },
            Child = new Image { Source = popup, Width = popupWidth - 2, Height = popupHeight - 2, Stretch = Stretch.Fill },
        };
        RenderOptions.SetBitmapScalingMode(surface.Child, BitmapScalingMode.HighQuality);
        root.Children.Add(surface);

        Save(root, Path.Combine(output, $"pastebird-{name}.png"));
    }

    private static Brush Backdrop(bool dark)
    {
        var brush = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 1) };
        if (dark)
        {
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0x0B, 0x12, 0x20), 0));
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0x10, 0x23, 0x4A), 0.6));
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0x1D, 0x4E, 0xD8), 1));
        }
        else
        {
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0xF7, 0xFA, 0xFD), 0));
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0xDB, 0xEA, 0xFE), 0.55));
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0x93, 0xC5, 0xFD), 1));
        }
        return brush;
    }

    /// <summary>Shows the real popup off-screen with sample data and renders its content.</summary>
    private BitmapSource RenderPopup(bool dark, string search, int select, bool preview, out double width, out double height)
    {
        var history = new ClipboardHistory(SampleItems(), 200);
        var popup = new PopupWindow(history, new LocalStorage())
        {
            ShowActivated = false,
            Left = -20000,
            Top = -20000,
        };
        popup.Prepare();
        Invoke(popup, "ApplyTheme");
        Theme(popup, dark); // the same brushes as ApplyTheme, but independent of the theme of this pc

        var searchBox = (TextBox)popup.FindName("SearchBox");
        if (search.Length > 0) searchBox.Text = search; else Invoke(popup, "Refresh", 0);
        Invoke(popup, "Select", select);
        if (preview)
        {
            typeof(PopupWindow).GetField("_showPreview", Private)!.SetValue(popup, true);
            Invoke(popup, "UpdatePreview");
        }

        popup.Show();
        popup.UpdateLayout();
        width = popup.ActualWidth;
        height = popup.ActualHeight;
        var bitmap = new RenderTargetBitmap((int)Math.Round(width * Scale), (int)Math.Round(height * Scale), 96 * Scale, 96 * Scale, PixelFormats.Pbgra32);
        bitmap.Render((Visual)popup.Content);
        bitmap.Freeze();
        popup.CloseForShutdown();
        return bitmap;
    }

    /// <summary>The brushes of PopupWindow.ApplyTheme for light or dark mode (keep in sync with it).</summary>
    private static void Theme(PopupWindow popup, bool dark)
    {
        byte ink = dark ? (byte)0xFF : (byte)0;
        void Set(string key, byte alpha) => popup.Resources[key] = new SolidColorBrush(Color.FromArgb(alpha, ink, ink, ink));
        popup.Resources["Surface"] = Brushes.Transparent;
        Set("TextPrimary", dark ? (byte)0xFF : (byte)0xE4);
        Set("TextSecondary", dark ? (byte)0xC5 : (byte)0x9E);
        Set("TextTertiary", dark ? (byte)0x87 : (byte)0x72);
        Set("Divider", dark ? (byte)0x19 : (byte)0x14);
        Set("Hover", dark ? (byte)0x0F : (byte)0x0A);
        Set("Selected", dark ? (byte)0x15 : (byte)0x0F);
        Set("ScrollThumb", dark ? (byte)0x8B : (byte)0x72);
        // Pastebird's blue instead of this pc's accent color, so the screenshots look the same everywhere.
        popup.Resources["Accent"] = new SolidColorBrush(dark ? Color.FromRgb(0x60, 0xA5, 0xFA) : Color.FromRgb(0x25, 0x63, 0xEB));
    }

    private List<ClipItem> SampleItems()
    {
        var now = DateTime.UtcNow;
        ClipItem Item(string content, ClipKind kind, double minutesAgo, bool pinned = false) =>
            new() { Content = content, Kind = kind, CopiedAt = now.AddMinutes(-minutesAgo), IsPinned = pinned };

        var screenshot = Item("sample-screenshot", ClipKind.Image, 9);
        screenshot.ImageWidth = 1920;
        screenshot.ImageHeight = 1080;
        screenshot.Thumbnail = FakeScreenshot();
        screenshot.ImageText = T("Q3 revenue dashboard · Sales by region · Europe 42%", "Omzet Q3 · Verkoop per regio · Europa 42%");

        return
        [
            Item(T("Kind regards,\r\nAlex Morgan\r\nProduct Designer, Northwind", "Met vriendelijke groet,\r\nAlex Morgan\r\nProductontwerper, Northwind"), ClipKind.Text, 4000, pinned: true),
            Item(T("42 Harbour Lane, Brighton BN1 4AB", "Havenstraat 42, 1011 AB Amsterdam"), ClipKind.Text, 9000, pinned: true),
            Item("https://github.com/pspeters/pastebird", ClipKind.Url, 1),
            Item(@"C:\Projects\website\index.php", ClipKind.FilePath, 3),
            screenshot,
            Item(T("Meeting moved to Thursday 10:00, room 4.12", "Overleg verplaatst naar donderdag 10:00, zaal 4.12"), ClipKind.Text, 10),
            Item("git checkout -b feature/search\r\ngit commit -am \"Add fuzzy search\"\r\ngit push -u origin feature/search", ClipKind.Text, 12),
            Item(T(@"C:\Users\alex\Pictures\logo.png" + "\r\n" + @"C:\Users\alex\Documents\report.pdf" + "\r\n" + @"C:\Users\alex\Documents\notes.txt",
                   @"C:\Users\alex\Pictures\logo.png" + "\r\n" + @"C:\Users\alex\Documents\rapport.pdf" + "\r\n" + @"C:\Users\alex\Documents\notities.txt"), ClipKind.Files, 26),
            Item(@"C:\Projects\api\Program.cs", ClipKind.FilePath, 40),
            Item(T("Thanks! I'll send the invoice before Friday.", "Bedankt! Ik stuur de factuur voor vrijdag."), ClipKind.Text, 55),
            Item("https://learn.microsoft.com/windows/apps/", ClipKind.Url, 70),
            Item("SELECT name, email FROM customers WHERE active = 1 ORDER BY name;", ClipKind.Text, 95),
            Item(T("Kickoff notes: scope, timeline and budget", "Notities kick-off: scope, planning en budget"), ClipKind.Text, 130),
        ];
    }

    /// <summary>A small thumbnail that looks like a screenshot of a dashboard.</summary>
    private static byte[] FakeScreenshot()
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0xF8, 0xFA, 0xFC)), null, new Rect(0, 0, 114, 64));
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x25, 0x63, 0xEB)), null, new Rect(0, 0, 114, 10));
            double[] bars = [18, 30, 24, 40, 34, 46];
            for (int i = 0; i < bars.Length; i++)
                dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x60, 0xA5, 0xFA)), null, new Rect(8 + i * 11, 58 - bars[i], 7, bars[i]));
            dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B)), null, new Point(94, 38), 13, 13);
            dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(0xF8, 0xFA, 0xFC)), null, new Point(94, 38), 6, 6);
        }
        var bitmap = new RenderTargetBitmap(114, 64, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        return Png(bitmap);
    }

    private static BitmapSource Logo()
    {
        var decoder = BitmapDecoder.Create(new Uri("pack://application:,,,/Pastebird;component/Assets/pastebird.ico"), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        return decoder.Frames.OrderByDescending(f => f.PixelWidth).First();
    }

    private static void Save(FrameworkElement element, string path)
    {
        element.Measure(new Size(element.Width, element.Height));
        element.Arrange(new Rect(0, 0, element.Width, element.Height));
        element.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)(element.Width * Scale), (int)(element.Height * Scale), 96 * Scale, 96 * Scale, PixelFormats.Pbgra32);
        bitmap.Render(element);
        File.WriteAllBytes(path, Png(bitmap));
        Console.WriteLine(path);
    }

    private static byte[] Png(BitmapSource bitmap)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    private static object? Invoke(object target, string method, params object[] args)
        => target.GetType().GetMethod(method, Private)!.Invoke(target, args);
}
