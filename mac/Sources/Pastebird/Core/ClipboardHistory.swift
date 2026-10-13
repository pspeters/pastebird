import Foundation

/// The in-memory history: pinned items first, then the rest newest first. Copying something that already
/// exists moves it to the top instead of creating a duplicate. Only unpinned items count towards
/// `maxItems` and are removed by `clear`. Of the unpinned items, at most `maxImages` are images.
final class ClipboardHistory {
    static let maxImages = 50

    private(set) var items: [ClipItem]
    private var removed: [[(index: Int, item: ClipItem)]] = []
    private var _maxItems: Int
    private var observers: [() -> Void] = []

    init(items: [ClipItem], maxItems: Int) {
        let valid = items.filter { !$0.content.isEmpty }
        self.items = valid.filter { $0.isPinned } + valid.filter { !$0.isPinned }
        _maxItems = maxItems
        trim()
    }

    /// Runs `handler` after every change.
    func observe(_ handler: @escaping () -> Void) { observers.append(handler) }

    private func changed() { observers.forEach { $0() } }

    /// True when `clear` would remove something.
    var hasUnpinnedItems: Bool { items.count > pinnedCount }

    private var pinnedCount: Int {
        var count = 0
        while count < items.count && items[count].isPinned { count += 1 }
        return count
    }

    var maxItems: Int {
        get { _maxItems }
        set {
            _maxItems = max(1, newValue)
            if trim() { changed() }
        }
    }

    private func index(sameAs item: ClipItem) -> Int? {
        let isImage = item.kind == .image
        return items.firstIndex { $0.content == item.content && ($0.kind == .image) == isImage }
    }

    /// Adds a copied item, or moves the existing item with the same content to the top and takes over the details
    /// of `copied`. Returns the item that is now in the history.
    @discardableResult
    func add(_ copied: ClipItem) -> ClipItem {
        guard let index = index(sameAs: copied) else {
            copied.copiedAt = Date()
            items.insert(copied, at: pinnedCount)
            trim()
            changed()
            return copied
        }

        let item = items[index]
        let same = item.kind == copied.kind && item.hasFormatting == copied.hasFormatting
        item.kind = copied.kind
        item.hasFormatting = copied.hasFormatting
        item.imageWidth = copied.imageWidth
        item.imageHeight = copied.imageHeight
        item.thumbnail = copied.thumbnail

        if item.isPinned {
            // Pinned items keep their place; just remember it was copied again.
            item.copiedAt = Date()
            changed()
            return item
        }
        if index == pinnedCount && same {
            return item // same as the most recent item: nothing to do
        }

        items.remove(at: index)
        item.copiedAt = Date()
        items.insert(item, at: pinnedCount)
        changed()
        return item
    }

    /// Marks an item as used and moves it to the top (of the unpinned items; pinned items stay put).
    func promote(_ item: ClipItem) {
        item.lastUsedAt = Date()
        if !item.isPinned, let index = items.firstIndex(where: { $0 === item }) {
            items.remove(at: index)
            items.insert(item, at: pinnedCount)
        }
        changed()
    }

    /// Pins an item (to the top of the list) or unpins it (to the top of the unpinned items).
    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        item.isPinned.toggle()
        items.insert(item, at: item.isPinned ? 0 : pinnedCount)
        trim()
        changed()
    }

    /// Removes an item. With `undoable`, `undo` can bring it back.
    func remove(_ item: ClipItem, undoable: Bool = false) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        if undoable { removed.append([(index: index, item: item)]) }
        changed()
    }

    /// Removes all unpinned items. With `undoable`, `undo` can bring them back.
    func clear(undoable: Bool = false) {
        guard hasUnpinnedItems else { return }
        let start = pinnedCount
        if undoable { removed.append(items[start...].enumerated().map { (index: start + $0.offset, item: $0.element) }) }
        items.removeSubrange(start...)
        changed()
    }

    /// Items removed with undo, newest action first. Their images and formatting are kept until `forgetRemoved`.
    var recentlyRemoved: [ClipItem] { removed.reversed().flatMap { $0.map(\.item) } }

    var canUndo: Bool { !removed.isEmpty }

    /// Brings back the items of the last undoable remove or clear, at their old place. Returns them.
    @discardableResult
    func undo() -> [ClipItem] {
        guard let action = removed.popLast() else { return [] }
        var restored: [ClipItem] = []
        for (index, item) in action {
            // Copied again in the meantime: the item is already back.
            if self.index(sameAs: item) != nil { continue }

            // Pinned items go back among the pinned ones, the others below them.
            let pinned = pinnedCount
            let at = item.isPinned ? min(index, pinned) : min(max(index, pinned), items.count)
            items.insert(item, at: at)
            restored.append(item)
        }
        trim()
        changed()
        return restored
    }

    /// Ends the chance to undo (when the popup closes), so the removed items' files can be deleted.
    func forgetRemoved() {
        guard !removed.isEmpty else { return }
        removed.removeAll()
        changed() // saving removes the files that are no longer needed
    }

    func contains(_ item: ClipItem) -> Bool { items.contains { $0 === item } }

    /// Stores the text recognized in an image, if the item is still in the history.
    func setImageText(_ item: ClipItem, _ text: String) {
        guard contains(item) else { return }
        item.imageText = text
        changed()
    }

    /// Removes the unpinned items copied before `cutoff`. Returns true when something was removed.
    @discardableResult
    func removeCopied(before cutoff: Date) -> Bool {
        let count = items.count
        items.removeAll { !$0.isPinned && $0.copiedAt < cutoff }
        guard items.count != count else { return false }
        changed()
        return true
    }

    @discardableResult
    private func trim() -> Bool {
        var trimmed = false
        let limit = pinnedCount + _maxItems
        if items.count > limit {
            items.removeSubrange(limit...)
            trimmed = true
        }

        // Images take far more space than text, so only the most recent ones are kept.
        var images = 0
        var i = pinnedCount
        while i < items.count {
            if items[i].kind == .image {
                images += 1
                if images > Self.maxImages {
                    items.remove(at: i)
                    trimmed = true
                    continue
                }
            }
            i += 1
        }
        return trimmed
    }
}
