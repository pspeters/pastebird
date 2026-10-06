using System.Collections.Specialized;
using System.IO;
using System.Windows;
using System.Windows.Threading;
using Pastebird.Core;
using static Pastebird.Interop.NativeMethods;

namespace Pastebird.Services;

/// <summary>
/// Listens for clipboard changes (AddClipboardFormatListener) and reports new text (with its formatting),
/// URLs, file lists and images. Content that password managers mark as private is skipped.
/// </summary>
internal sealed class ClipboardMonitor : IDisposable
{
    private const int MaxChars = 200_000;
    private const int MaxFormattingChars = 2_000_000;

    private readonly MessageWindow _window;
    private readonly DispatcherTimer _debounce;
    private readonly uint _excludeFormat = RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing");
    private readonly uint _viewerIgnoreFormat = RegisterClipboardFormat("Clipboard Viewer Ignore");
    private readonly uint _canIncludeFormat = RegisterClipboardFormat("CanIncludeInClipboardHistory");
    private uint _ownSequence;

    public ClipboardMonitor(MessageWindow window)
    {
        _window = window;
        // Apps often write the clipboard in several steps; wait briefly and read once.
        _debounce = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(60) };
        _debounce.Tick += (_, _) => { _debounce.Stop(); ReadClipboard(); };
        _window.Message += OnMessage;
        AddClipboardFormatListener(_window.Handle);
    }

    /// <summary>Raised with a new item (not yet in the history) and its formatting or image, if any.</summary>
    public event Action<ClipItem, ClipData?>? Captured;

    /// <summary>
    /// Puts an item back on the clipboard: text with its formatting unless <paramref name="keepFormatting"/> is false,
    /// images as PNG and bitmap, and file lists as real files when they still exist.
    /// </summary>
    public void SetClipboard(ClipItem item, ClipData? stored, bool keepFormatting)
    {
        var data = new DataObject();
        if (item.Kind == ClipKind.Image)
        {
            if (stored?.Png is not { } png)
                throw new InvalidOperationException("The image of this item is missing.");
            data.SetData("PNG", new MemoryStream(png), false);
            data.SetImage(ClipImages.Decode(png));
        }
        else
        {
            if (keepFormatting && stored is not null)
            {
                if (stored.Html is not null) data.SetData(DataFormats.Html, stored.Html);
                if (stored.Rtf is not null) data.SetData(DataFormats.Rtf, stored.Rtf);
            }
            data.SetData(DataFormats.UnicodeText, item.Content);
        }

        if (item.Kind == ClipKind.Files)
        {
            var files = item.Content.Split("\r\n", StringSplitOptions.RemoveEmptyEntries);
            if (files.All(f => File.Exists(f) || Directory.Exists(f)))
            {
                var list = new StringCollection();
                list.AddRange(files);
                data.SetFileDropList(list);
            }
        }

        Clipboard.SetDataObject(data, copy: true);
        _ownSequence = GetClipboardSequenceNumber();
    }

    private void OnMessage(int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg != WM_CLIPBOARDUPDATE) return;
        _debounce.Stop();
        _debounce.Start();
        handled = true;
    }

    private void ReadClipboard()
    {
        if (GetClipboardSequenceNumber() == _ownSequence)
            return; // our own write; the history was already updated
        if (IsClipboardFormatAvailable(_excludeFormat) || IsClipboardFormatAvailable(_viewerIgnoreFormat))
            return;

        try
        {
            var data = Clipboard.GetDataObject();
            if (data is null) return;
            if (IsClipboardFormatAvailable(_canIncludeFormat) && !CanIncludeInHistory(data))
                return;

            if (data.GetDataPresent(DataFormats.FileDrop) && data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files)
            {
                Captured?.Invoke(new ClipItem { Content = string.Join("\r\n", files), Kind = ClipKind.Files }, null);
            }
            else if (data.GetDataPresent(DataFormats.UnicodeText, true) && data.GetData(DataFormats.UnicodeText, true) is string text
                     && !string.IsNullOrWhiteSpace(text))
            {
                // Text wins over an image: apps like Excel and Word also put a picture of copied text on the clipboard.
                if (text.Length > MaxChars) return;
                var formatting = ReadFormatting(data);
                Captured?.Invoke(new ClipItem { Content = text, Kind = ClipItem.DetectKind(text), HasFormatting = formatting is not null }, formatting);
            }
            else if (ClipImages.Read(data) is { } image)
            {
                _ = CaptureImageAsync(image);
            }
        }
        catch (Exception ex)
        {
            // The clipboard can be locked by another app or hold broken data; skip this change.
            LocalStorage.Log(ex);
        }
    }

    private static ClipData? ReadFormatting(IDataObject data)
    {
        var html = ReadFormat(data, DataFormats.Html);
        var rtf = ReadFormat(data, DataFormats.Rtf);
        return html is null && rtf is null ? null : new ClipData { Html = html, Rtf = rtf };
    }

    private static string? ReadFormat(IDataObject data, string format)
        => data.GetDataPresent(format, false) && data.GetData(format, false) is string { Length: > 0 and <= MaxFormattingChars } value
            ? value
            : null;

    /// <summary>Encodes the image and its thumbnail in the background, so a large screenshot doesn't block the UI.</summary>
    private async Task CaptureImageAsync(ClipboardImage image)
    {
        try
        {
            if (await Task.Run(() => ClipImages.Create(image)) is var (item, data))
                Captured?.Invoke(item, data);
        }
        catch (Exception ex)
        {
            LocalStorage.Log(ex);
        }
    }

    private static bool CanIncludeInHistory(IDataObject data)
    {
        if (data.GetData("CanIncludeInClipboardHistory") is MemoryStream { Length: >= 4 } stream)
        {
            var buffer = new byte[4];
            stream.ReadExactly(buffer);
            return BitConverter.ToInt32(buffer) != 0;
        }
        return true;
    }

    public void Dispose()
    {
        _debounce.Stop();
        _window.Message -= OnMessage;
        RemoveClipboardFormatListener(_window.Handle);
    }
}
