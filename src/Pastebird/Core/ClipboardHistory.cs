namespace Pastebird.Core;

/// <summary>
/// The in-memory history: pinned items first, then the rest newest first. Copying something that already
/// exists moves it to the top instead of creating a duplicate. Only unpinned items count towards
/// <see cref="MaxItems"/> and are removed by <see cref="Clear"/>. Of the unpinned items, at most
/// <see cref="MaxImages"/> are images.
/// </summary>
public sealed class ClipboardHistory
{
    public const int MaxImages = 50;

    private readonly List<ClipItem> _items;
    private readonly Stack<List<(int Index, ClipItem Item)>> _removed = new();
    private int _maxItems;

    public ClipboardHistory(IEnumerable<ClipItem> items, int maxItems)
    {
        var valid = items.Where(i => !string.IsNullOrEmpty(i.Content)).ToList();
        _items = [.. valid.Where(i => i.IsPinned), .. valid.Where(i => !i.IsPinned)];
        _maxItems = maxItems;
        Trim();
    }

    public event Action? Changed;

    public IReadOnlyList<ClipItem> Items => _items;

    /// <summary>True when <see cref="Clear"/> would remove something.</summary>
    public bool HasUnpinnedItems => _items.Count > PinnedCount;

    private int PinnedCount
    {
        get
        {
            int count = 0;
            while (count < _items.Count && _items[count].IsPinned) count++;
            return count;
        }
    }

    public int MaxItems
    {
        get => _maxItems;
        set
        {
            _maxItems = Math.Max(1, value);
            if (Trim()) Changed?.Invoke();
        }
    }

    /// <summary>
    /// Adds a copied item, or moves the existing item with the same content to the top and takes over the details
    /// of <paramref name="copied"/>. Returns the item that is now in the history.
    /// </summary>
    public ClipItem Add(ClipItem copied)
    {
        bool isImage = copied.Kind == ClipKind.Image;
        int index = _items.FindIndex(i => i.Content == copied.Content && (i.Kind == ClipKind.Image) == isImage);
        if (index < 0)
        {
            copied.CopiedAt = DateTime.UtcNow;
            _items.Insert(PinnedCount, copied);
            Trim();
            Changed?.Invoke();
            return copied;
        }

        var item = _items[index];
        bool same = item.Kind == copied.Kind && item.HasFormatting == copied.HasFormatting;
        item.Kind = copied.Kind;
        item.HasFormatting = copied.HasFormatting;
        item.ImageWidth = copied.ImageWidth;
        item.ImageHeight = copied.ImageHeight;
        item.Thumbnail = copied.Thumbnail;

        if (item.IsPinned)
        {
            // Pinned items keep their place; just remember it was copied again.
            item.CopiedAt = DateTime.UtcNow;
            Changed?.Invoke();
            return item;
        }
        if (index == PinnedCount && same)
            return item; // same as the most recent item: nothing to do

        _items.RemoveAt(index);
        item.CopiedAt = DateTime.UtcNow;
        _items.Insert(PinnedCount, item);
        Changed?.Invoke();
        return item;
    }

    /// <summary>Marks an item as used and moves it to the top (of the unpinned items; pinned items stay put).</summary>
    public void Promote(ClipItem item)
    {
        item.LastUsedAt = DateTime.UtcNow;
        if (!item.IsPinned && _items.Remove(item))
            _items.Insert(PinnedCount, item);
        Changed?.Invoke();
    }

    /// <summary>Pins an item (to the top of the list) or unpins it (to the top of the unpinned items).</summary>
    public void TogglePin(ClipItem item)
    {
        if (!_items.Remove(item)) return;
        item.IsPinned = !item.IsPinned;
        _items.Insert(item.IsPinned ? 0 : PinnedCount, item);
        Trim();
        Changed?.Invoke();
    }

    /// <summary>Removes an item. With <paramref name="undoable"/>, <see cref="Undo"/> can bring it back.</summary>
    public void Remove(ClipItem item, bool undoable = false)
    {
        int index = _items.IndexOf(item);
        if (index < 0) return;
        _items.RemoveAt(index);
        if (undoable) _removed.Push([(index, item)]);
        Changed?.Invoke();
    }

    /// <summary>Removes all unpinned items. With <paramref name="undoable"/>, <see cref="Undo"/> can bring them back.</summary>
    public void Clear(bool undoable = false)
    {
        if (!HasUnpinnedItems) return;
        int start = PinnedCount;
        if (undoable) _removed.Push([.. _items.Skip(start).Select((item, i) => (start + i, item))]);
        _items.RemoveRange(start, _items.Count - start);
        Changed?.Invoke();
    }

    /// <summary>Items removed with undo, newest action first. Their images and formatting are kept until <see cref="ForgetRemoved"/>.</summary>
    public IEnumerable<ClipItem> RecentlyRemoved => _removed.SelectMany(action => action.Select(r => r.Item));

    public bool CanUndo => _removed.Count > 0;

    /// <summary>Brings back the items of the last undoable remove or clear, at their old place. Returns them.</summary>
    public List<ClipItem> Undo()
    {
        if (!_removed.TryPop(out var action)) return [];
        var restored = new List<ClipItem>();
        foreach (var (index, item) in action)
        {
            // Copied again in the meantime: the item is already back.
            bool isImage = item.Kind == ClipKind.Image;
            if (_items.Any(i => i.Content == item.Content && (i.Kind == ClipKind.Image) == isImage)) continue;

            // Pinned items go back among the pinned ones, the others below them.
            int pinned = PinnedCount;
            _items.Insert(item.IsPinned ? Math.Min(index, pinned) : Math.Clamp(index, pinned, _items.Count), item);
            restored.Add(item);
        }
        Trim();
        Changed?.Invoke();
        return restored;
    }

    /// <summary>Ends the chance to undo (when the popup closes), so the removed items' files can be deleted.</summary>
    public void ForgetRemoved()
    {
        if (_removed.Count == 0) return;
        _removed.Clear();
        Changed?.Invoke(); // saving removes the files that are no longer needed
    }

    /// <summary>Stores the text recognized in an image, if the item is still in the history.</summary>
    public void SetImageText(ClipItem item, string text)
    {
        if (!_items.Contains(item)) return;
        item.ImageText = text;
        Changed?.Invoke();
    }

    /// <summary>Removes the unpinned items copied before <paramref name="cutoffUtc"/>. Returns true when something was removed.</summary>
    public bool RemoveCopiedBefore(DateTime cutoffUtc)
    {
        if (_items.RemoveAll(i => !i.IsPinned && i.CopiedAt < cutoffUtc) == 0) return false;
        Changed?.Invoke();
        return true;
    }

    private bool Trim()
    {
        bool trimmed = false;
        int limit = PinnedCount + _maxItems;
        if (_items.Count > limit)
        {
            _items.RemoveRange(limit, _items.Count - limit);
            trimmed = true;
        }

        // Images take far more space than text, so only the most recent ones are kept.
        int images = 0;
        for (int i = PinnedCount; i < _items.Count; i++)
        {
            if (_items[i].Kind == ClipKind.Image && ++images > MaxImages)
            {
                _items.RemoveAt(i--);
                trimmed = true;
            }
        }
        return trimmed;
    }
}
