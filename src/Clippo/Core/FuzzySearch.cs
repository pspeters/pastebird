namespace Clippo.Core;

/// <summary>
/// Small realtime fuzzy search. Every space-separated term must match, either as a substring
/// (ranked highest) or as an in-order subsequence ("proj" → "C:\Projecten\..."). Ties keep recency order.
/// </summary>
public static class FuzzySearch
{
    public static List<ClipItem> Filter(IReadOnlyList<ClipItem> items, string query)
    {
        var terms = query.Trim().ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (terms.Length == 0)
            return items.ToList();

        var matches = new List<(ClipItem Item, int Score, int Index)>();
        for (int i = 0; i < items.Count; i++)
        {
            var text = items[i].SearchText;
            int total = 0;
            foreach (var term in terms)
            {
                int score = Score(text, term);
                if (score < 0) { total = -1; break; }
                total += score;
            }
            if (total >= 0)
                matches.Add((items[i], total, i));
        }

        matches.Sort((a, b) => a.Score != b.Score ? b.Score.CompareTo(a.Score) : a.Index.CompareTo(b.Index));
        return matches.ConvertAll(m => m.Item);
    }

    /// <summary>Returns -1 for no match; substring matches always outrank subsequence matches.</summary>
    internal static int Score(string text, string term)
    {
        int index = text.IndexOf(term, StringComparison.Ordinal);
        if (index >= 0)
            return 1000 + (IsWordStart(text, index) ? 200 : 0) - Math.Min(index, 300);

        int score = 0, matched = 0, last = -1, streak = 0;
        for (int i = 0; i < text.Length && matched < term.Length; i++)
        {
            if (text[i] != term[matched]) continue;

            if (last == i - 1) score += 5 * ++streak;
            else
            {
                streak = 0;
                if (last >= 0) score -= Math.Min(i - last - 1, 10);
            }
            if (IsWordStart(text, i)) score += 10;
            last = i;
            matched++;
        }
        return matched == term.Length ? Math.Clamp(100 + score, 1, 600) : -1;
    }

    private static bool IsWordStart(string text, int i) => i == 0 || !char.IsLetterOrDigit(text[i - 1]);
}
