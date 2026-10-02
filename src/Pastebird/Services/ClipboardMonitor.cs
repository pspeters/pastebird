using System.Collections.Specialized;
using System.IO;
using System.Windows;
using System.Windows.Threading;
using Pastebird.Core;
using static Pastebird.Interop.NativeMethods;

namespace Pastebird.Services;

/// <summary>
/// Listens for clipboard changes (AddClipboardFormatListener) and reports new text, URLs and file lists.
/// Content that password managers mark as private is skipped.
/// </summary>
internal sealed class ClipboardMonitor : IDisposable
{
    private const int MaxChars = 200_000;

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

    public event Action<string, ClipKind>? Captured;

    /// <summary>Puts an item back on the clipboard. File lists are restored as real files when they still exist.</summary>
    public void SetClipboard(ClipItem item)
    {
        var data = new DataObject();
        data.SetData(DataFormats.UnicodeText, item.Content);

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
                Captured?.Invoke(string.Join("\r\n", files), ClipKind.Files);
            }
            else if (data.GetDataPresent(DataFormats.UnicodeText, true) && data.GetData(DataFormats.UnicodeText, true) is string text)
            {
                if (string.IsNullOrWhiteSpace(text) || text.Length > MaxChars) return;
                Captured?.Invoke(text, ClipItem.DetectKind(text));
            }
        }
        catch (Exception ex)
        {
            // The clipboard can be locked by another app or hold broken data; skip this change.
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
