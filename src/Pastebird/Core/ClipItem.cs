using System.IO;
using System.Text;
using System.Text.Json.Serialization;

namespace Pastebird.Core;

public enum ClipKind { Text, Url, FilePath, Files, Image }

/// <summary>One entry in the clipboard history.</summary>
public sealed class ClipItem
{
    private ClipKind _kind;
    private string? _preview;
    private string? _searchText;

    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>The text, URL, path or file list. For images: the SHA-256 of the PNG, to recognize the same image again.</summary>
    public string Content { get; set; } = "";
    public DateTime CopiedAt { get; set; }
    public DateTime? LastUsedAt { get; set; }

    /// <summary>Pinned items stay at the top, don't count towards the history size and survive "Clear history".</summary>
    public bool IsPinned { get; set; }

    /// <summary>True when the formatting of copied text (HTML/RTF) is stored next to it, see <see cref="ClipData"/>.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public bool HasFormatting { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public int ImageWidth { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public int ImageHeight { get; set; }

    /// <summary>Small PNG shown in the popup for images; the full image is in <see cref="ClipData"/>.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public byte[]? Thumbnail { get; set; }

    /// <summary>True when the item has a <see cref="ClipData"/> file next to the history.</summary>
    [JsonIgnore]
    public bool HasData => HasFormatting || Kind == ClipKind.Image;

    public ClipKind Kind
    {
        get => _kind;
        set { _kind = value; _preview = null; }
    }

    /// <summary>Single-line text shown in the popup.</summary>
    [JsonIgnore]
    public string Preview => Kind is ClipKind.Files or ClipKind.Image ? BuildPreview() : _preview ??= BuildPreview(); // these contain translated text

    /// <summary>Segoe Fluent Icons glyph for the item type.</summary>
    [JsonIgnore]
    public string Glyph => Kind switch
    {
        ClipKind.Url => "",      // Link
        ClipKind.FilePath => "", // Document
        ClipKind.Files => "",    // Folder
        ClipKind.Image => "", // Photo
        _ => "",                 // AlignLeft (text)
    };

    /// <summary>Lower-cased (and capped) content used by the search.</summary>
    internal string SearchText => Kind == ClipKind.Image ? Preview.ToLowerInvariant() : _searchText ??= (Content.Length > 10_000 ? Content[..10_000] : Content).ToLowerInvariant();

    private string BuildPreview()
    {
        if (Kind == ClipKind.Image)
            return Loc.T("item.image", ImageWidth, ImageHeight);
        if (Kind == ClipKind.Files)
        {
            var files = Content.Split("\r\n", StringSplitOptions.RemoveEmptyEntries);
            if (files.Length > 1)
                return Loc.T("item.files", files.Length) + string.Join(", ", files.Take(6).Select(Path.GetFileName));
        }

        // Collapse all whitespace (newlines, tabs) so multi-line text fits on one row.
        var source = Content.Length > 400 ? Content.AsSpan(0, 400) : Content.AsSpan();
        var sb = new StringBuilder(source.Length);
        bool space = false;
        foreach (var c in source)
        {
            if (char.IsWhiteSpace(c)) { space = sb.Length > 0; continue; }
            if (space) { sb.Append(' '); space = false; }
            sb.Append(c);
        }
        return sb.ToString();
    }

    /// <summary>Decides whether copied text is a URL, a file path or plain text.</summary>
    public static ClipKind DetectKind(string text)
    {
        var t = text.Trim().Trim('"');
        if (t.Length == 0 || t.Length > 2048 || t.Contains('\n'))
            return ClipKind.Text;
        if (LooksLikePath(t))
            return ClipKind.FilePath;
        if (t.Contains(' '))
            return ClipKind.Text;
        if (Uri.TryCreate(t, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" or "ftp" or "mailto")
            return ClipKind.Url;
        if (t.StartsWith("www.", StringComparison.OrdinalIgnoreCase) && t.IndexOf('.', 4) > 4)
            return ClipKind.Url;
        return ClipKind.Text;
    }

    private static bool LooksLikePath(string t)
        => (t.Length >= 3 && char.IsAsciiLetter(t[0]) && t[1] == ':' && t[2] is '\\' or '/')
           || (t.Length > 3 && t.StartsWith(@"\\"));
}
