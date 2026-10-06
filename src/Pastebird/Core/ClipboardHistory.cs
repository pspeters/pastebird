namespace Pastebird.Core;

/// <summary>
/// The in-memory history: pinned items first, then the rest newest first. Copying something that already
/// exists moves it to the top instead of creating a duplicate. Only unpinned items count towards
/// <see cref="MaxItems"/> and are removed by <see cref="Clear"/>.
/// </summary>
public sealed class ClipboardHistory
{
    private readonly List<ClipItem> _items;
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

    public void Remove(ClipItem item)
    {
        if (_items.Remove(item))
            Changed?.Invoke();
    }

    /// <summary>Removes all unpinned items.</summary>
    public void Clear()
    {
        if (!HasUnpinnedItems) return;
        _items.RemoveRange(PinnedCount, _items.Count - PinnedCount);
        Changed?.Invoke();
    }

    private bool Trim()
    {
        int limit = PinnedCount + _maxItems;
        if (_items.Count <= limit) return false;
        _items.RemoveRange(limit, _items.Count - limit);
        return true;
    }
}
