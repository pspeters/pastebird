using System.IO;
using System.Reflection;
using System.Text.RegularExpressions;

namespace Pastebird.Core;

public sealed record ChangelogSection(string Type, IReadOnlyList<string> Items);

public sealed record ChangelogRelease(Version Version, string Date, IReadOnlyList<ChangelogSection> Sections);

/// <summary>
/// The repository's CHANGELOG.md, embedded in the app at build time, so "What's new" works offline.
/// Understands "## [1.2.0] - date", "### Added" and "- item" lines; everything else is ignored.
/// </summary>
public static partial class Changelog
{
    public static IReadOnlyList<ChangelogRelease> Load()
    {
        try
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("CHANGELOG.md");
            return stream is null ? [] : Parse(new StreamReader(stream).ReadToEnd());
        }
        catch (Exception ex)
        {
            LocalStorage.Log(ex);
            return [];
        }
    }

    /// <summary>Releases newer than <paramref name="previous"/> up to and including <paramref name="current"/>, newest first.</summary>
    public static IReadOnlyList<ChangelogRelease> Between(Version? previous, Version current)
        => Load().Where(r => r.Version <= current && (previous is null || r.Version > previous)).ToList();

    public static IReadOnlyList<ChangelogRelease> Parse(string markdown)
    {
        markdown = CommentRegex().Replace(markdown, "");
        var releases = new List<(Version Version, string Date, List<(string Type, List<string> Items)> Sections)>();
        foreach (var raw in markdown.Split('\n'))
        {
            var line = raw.TrimEnd('\r');
            if (ReleaseRegex().Match(line) is { Success: true } release)
            {
                releases.Add((Version.Parse(release.Groups[1].Value), release.Groups[2].Value, []));
            }
            else if (releases.Count > 0 && line.StartsWith("### "))
            {
                releases[^1].Sections.Add((line[4..].Trim(), []));
            }
            else if (releases.Count > 0 && (line.StartsWith("- ") || line.StartsWith("* ")))
            {
                if (releases[^1].Sections.Count == 0) releases[^1].Sections.Add(("", []));
                releases[^1].Sections[^1].Items.Add(line[2..].Trim());
            }
        }
        return releases
            .Select(r => new ChangelogRelease(r.Version, r.Date,
                r.Sections.Where(s => s.Items.Count > 0).Select(s => new ChangelogSection(s.Type, s.Items)).ToList()))
            .ToList();
    }

    /// <summary>Splits "Press **Ctrl+P** to `pin`" into (text, bold) runs; links become their text.</summary>
    public static IEnumerable<(string Text, bool Bold)> InlineRuns(string item)
    {
        item = LinkRegex().Replace(item, "$1").Replace("`", "");
        var parts = item.Split("**");
        for (int i = 0; i < parts.Length; i++)
            if (parts[i].Length > 0)
                yield return (parts[i], i % 2 == 1);
    }

    [GeneratedRegex(@"<!--.*?-->", RegexOptions.Singleline)]
    private static partial Regex CommentRegex();

    [GeneratedRegex(@"^## \[(\d+\.\d+\.\d+)\](?:\s*-\s*(\S+))?")]
    private static partial Regex ReleaseRegex();

    [GeneratedRegex(@"\[([^\]]+)\]\([^)]+\)")]
    private static partial Regex LinkRegex();
}
