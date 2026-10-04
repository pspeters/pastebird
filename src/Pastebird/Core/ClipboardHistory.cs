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

    public void Add(string content, ClipKind kind)
    {
        int index = _items.FindIndex(i => i.Content == content);
        if (index >= 0 && _items[index].IsPinned)
        {
            // Pinned items keep their place; just remember it was copied again.
            _items[index].Kind = kind;
            _items[index].CopiedAt = DateTime.UtcNow;
            Changed?.Invoke();
            return;
        }
        if (index >= 0 && index == PinnedCount && _items[index].Kind == kind)
            return; // same as the most recent item: nothing to do

        ClipItem item;
        if (index >= 0)
        {
            item = _items[index];
            _items.RemoveAt(index);
            item.Kind = kind;
        }
        else
        {
            item = new ClipItem { Content = content, Kind = kind };
        }

        item.CopiedAt = DateTime.UtcNow;
        _items.Insert(PinnedCount, item);
        Trim();
        Changed?.Invoke();
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
