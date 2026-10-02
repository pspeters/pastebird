namespace Pastebird.Core;

/// <summary>
/// The in-memory history, newest first. Copying something that already exists moves it to the top
/// instead of creating a duplicate, and the list never grows beyond <see cref="MaxItems"/>.
/// </summary>
public sealed class ClipboardHistory
{
    private readonly List<ClipItem> _items;
    private int _maxItems;

    public ClipboardHistory(IEnumerable<ClipItem> items, int maxItems)
    {
        _items = items.Where(i => !string.IsNullOrEmpty(i.Content)).ToList();
        _maxItems = maxItems;
        Trim();
    }

    public event Action? Changed;

    public IReadOnlyList<ClipItem> Items => _items;

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
        if (index == 0 && _items[0].Kind == kind)
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
        _items.Insert(0, item);
        Trim();
        Changed?.Invoke();
    }

    /// <summary>Marks an item as used and moves it to the top.</summary>
    public void Promote(ClipItem item)
    {
        item.LastUsedAt = DateTime.UtcNow;
        if (_items.Remove(item))
            _items.Insert(0, item);
        Changed?.Invoke();
    }

    public void Remove(ClipItem item)
    {
        if (_items.Remove(item))
            Changed?.Invoke();
    }

    public void Clear()
    {
        if (_items.Count == 0) return;
        _items.Clear();
        Changed?.Invoke();
    }

    private bool Trim()
    {
        if (_items.Count <= _maxItems) return false;
        _items.RemoveRange(_maxItems, _items.Count - _maxItems);
        return true;
    }
}
