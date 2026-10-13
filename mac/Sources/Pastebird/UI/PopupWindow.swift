import AppKit
import Carbon.HIToolbox

enum PopupPlacement {
    /// Upper middle of the screen with the active window (keyboard use).
    case centered
    /// Below the menu bar icon (its frame on screen).
    case belowStatusItem(NSRect)
}

/// A panel that takes keyboard focus without activating Pastebird, so the app you were in stays active
/// (like Spotlight). Every key press goes through `keyHandler` first, like PreviewKeyDown in WPF.
final class PopupPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    // ⌘-combinations arrive here first, before the menu (⌘Z) or sendEvent see them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// The Pastebird popup: a search box and the recent items. The panel is created once and
/// only hidden/shown afterwards, so it appears instantly.
final class PopupWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private static let width: CGFloat = 520
    private static let searchHeight: CGFloat = 50
    private static let listMaxHeight: CGFloat = 370
    private static let textRowHeight: CGFloat = 34
    private static let imageRowHeight: CGFloat = 48
    private static let previewTextHeight: CGFloat = 150
    private static let previewHeight: CGFloat = 1 + 6 + 22 + previewTextHeight + 6

    // Characters shown in the preview pane; the rest is summarized.
    private static let previewLimit = 5_000

    // Images in the preview pane are decoded at most this large (enough for the pane on a Retina display).
    private static let previewImagePixels = 1000

    private let history: ClipboardHistory
    private let storage: LocalStorage
    private var results: [ClipItem] = []
    private var selectedIndex = -1
    private var showPreview = false
    private var hiding = false
    private var hiddenAt = Date.distantPast
    private var previewImage: (hash: String, image: NSImage)?
    private let thumbnails = NSCache<NSString, NSImage>()

    // Placement, in screen points.
    private var visibleFrame = NSRect.zero
    private var anchorTop: CGFloat = 0
    private var anchorX: CGFloat = 0

    private let panel: PopupPanel
    private let content = FlippedView()
    private let searchIcon = NSImageView()
    private let searchField = NSTextField()
    private let undoHint = NSTextField(labelWithString: "")
    private let divider = SeparatorLine()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let previewPane = FlippedView()
    private let previewDivider = SeparatorLine()
    private let copiedLabel = NSTextField(labelWithString: "")
    private let previewTextScroll = NSTextView.scrollableTextView()
    private var previewText: NSTextView { previewTextScroll.documentView as! NSTextView }
    private let previewImageView = NSImageView()

    /// Called when the user picks an item, with whether it should also be pasted and whether the formatting
    /// of copied text should be kept (false with ⌘↩).
    var itemChosen: ((ClipItem, Bool, Bool) -> Void)?

    /// Called on ⌘, in the popup.
    var settingsRequested: (() -> Void)?

    /// True right after the popup closed; lets a click on the menu bar icon toggle it instead of reopening it.
    var wasJustHidden: Bool { Date().timeIntervalSince(hiddenAt) < 0.4 }

    var isVisible: Bool { panel.isVisible }

    init(history: ClipboardHistory, storage: LocalStorage) {
        self.history = history
        self.storage = storage
        panel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                           backing: .buffered, defer: false)
        super.init()
        buildPanel()
        history.observe { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.refresh(preferredIndex: self.selectedIndex)
        }
    }

    // ---------------------------------------------------------------- show & hide

    func show(_ placement: PopupPlacement) {
        showPreview = false
        searchField.placeholderString = Loc.t("popup.search")
        searchField.stringValue = ""
        refresh()

        computeAnchor(placement)
        relayout()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        guard panel.isVisible, !hiding else { return }
        hiding = true
        hiddenAt = Date()
        panel.orderOut(nil)
        previewImage = nil // don't keep a large image in memory while hidden
        previewImageView.image = nil
        history.forgetRemoved() // removing is final once the popup closes
        hiding = false
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // ---------------------------------------------------------------- list

    private func refresh(preferredIndex: Int = 0) {
        results = FuzzySearch.filter(history.items, query: searchField.stringValue)
        tableView.reloadData()

        undoHint.stringValue = Loc.t("popup.undo")
        undoHint.isHidden = !history.canUndo
        emptyLabel.stringValue = Loc.t(history.items.isEmpty ? "popup.empty" : "popup.noResults")
        selectedIndex = results.isEmpty ? -1 : min(max(preferredIndex, 0), results.count - 1)
        select(selectedIndex)
    }

    private func select(_ index: Int) {
        guard !results.isEmpty else {
            selectedIndex = -1
            updatePreview()
            return
        }
        selectedIndex = min(max(index, 0), results.count - 1)
        tableView.enumerateAvailableRowViews { rowView, row in
            (rowView as? ClipRowView)?.isCurrent = row == self.selectedIndex
        }
        updatePreview()
        tableView.scrollRowToVisible(selectedIndex)
    }

    private var selectedItem: ClipItem? { results.indices.contains(selectedIndex) ? results[selectedIndex] : nil }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        results[row].thumbnail != nil ? Self.imageRowHeight : Self.textRowHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ClipRowView()
        rowView.isCurrent = row == selectedIndex
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ClipCellView.identifier, owner: self) as? ClipCellView ?? ClipCellView()
        let item = results[row]
        cell.configure(item, thumbnail: thumbnail(for: item))
        cell.onPin = { [weak self] in self?.togglePin(item) }
        cell.onRemove = { [weak self] in
            guard let self, let index = self.results.firstIndex(where: { $0 === item }) else { return }
            self.history.remove(item, undoable: true) // refreshes the list through the history observer
            self.select(index)
        }
        return cell
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard results.indices.contains(row) else { return }
        choose(results[row], paste: true)
    }

    private func thumbnail(for item: ClipItem) -> NSImage? {
        guard let data = item.thumbnail else { return nil }
        let key = "\(item.id.uuidString)-\(data.count)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let image = NSImage(data: data), let rep = image.representations.first else { return nil }
        image.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2) // stored at 2×
        thumbnails.setObject(image, forKey: key)
        return image
    }

    private func undo() {
        let restored = history.undo() // refreshes the list through the history observer
        if let first = restored.first, let index = results.firstIndex(where: { $0 === first }) {
            select(index)
        }
    }

    private func togglePin(_ item: ClipItem) {
        history.togglePin(item) // refreshes the list through the history observer
        if let index = results.firstIndex(where: { $0 === item }) { select(index) }
    }

    private func choose(_ item: ClipItem, paste: Bool, keepFormatting: Bool = true) {
        hide()
        itemChosen?(item, paste, keepFormatting)
    }

    // ---------------------------------------------------------------- preview

    /// Shows the full content of the selected item below the list while the preview is on.
    private func updatePreview() {
        defer { relayout() }
        guard showPreview, let item = selectedItem else {
            previewPane.isHidden = true
            return
        }
        previewPane.isHidden = false

        let details = [
            item.copiedAt == .distantPast ? "" : Self.formatCopiedAt(item.copiedAt),
            item.hasFormatting ? Loc.t("popup.formatting") : "",
            (item.imageText ?? "").isEmpty ? "" : Loc.t("popup.imageText"),
        ]
        copiedLabel.stringValue = details.filter { !$0.isEmpty }.joined(separator: " · ")

        let isImage = item.kind == .image
        previewTextScroll.isHidden = isImage
        previewImageView.isHidden = !isImage
        if isImage {
            previewImageView.image = loadPreviewImage(item)
        } else {
            let text = item.content
            if text.count > Self.previewLimit {
                let more = NumberFormatter.localizedString(from: NSNumber(value: text.count - Self.previewLimit), number: .decimal)
                previewText.string = String(text.prefix(Self.previewLimit)) + Loc.t("popup.preview.more", more)
            } else {
                previewText.string = text
            }
            previewText.scroll(.zero)
        }
    }

    /// Decodes the image of an item for the preview pane; the last one is kept, so a redraw is instant.
    private func loadPreviewImage(_ item: ClipItem) -> NSImage? {
        if let cached = previewImage, cached.hash == item.content { return cached.image }
        guard let png = storage.loadData(item)?.png,
              let cg = ClipImages.downscaled(png, maxPixelSize: Self.previewImagePixels) else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        previewImage = (item.content, image)
        return image
    }

    /// "Copied 5 min ago", "Copied yesterday at 14:32", "Copied on 3 October at 09:15"…
    private static func formatCopiedAt(_ copied: Date) -> String {
        let now = Date()
        let locale = Loc.shared.locale
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let time = timeFormatter.string(from: copied)

        let minutes = Int(now.timeIntervalSince(copied) / 60)
        if minutes < 1 { return Loc.t("popup.copied.now") }
        if minutes < 60 { return Loc.t("popup.copied.minutes", minutes) }
        if calendar.isDateInToday(copied) { return Loc.t("popup.copied.today", time) }
        if calendar.isDateInYesterday(copied) { return Loc.t("popup.copied.yesterday", time) }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        if calendar.isDate(copied, equalTo: now, toGranularity: .year) {
            dateFormatter.setLocalizedDateFormatFromTemplate("dMMMM")
        } else {
            dateFormatter.dateStyle = .short
        }
        return Loc.t("popup.copied.date", dateFormatter.string(from: copied), time)
    }

    // ---------------------------------------------------------------- input

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    private var fieldEditor: NSTextView? { searchField.currentEditor() as? NSTextView }

    private func handleKey(_ event: NSEvent) -> Bool {
        if fieldEditor?.hasMarkedText() == true { return false } // composing text with an input method

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = mods.contains(.command)
        let shift = mods.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
        case kVK_DownArrow:
            select(selectedIndex + 1)
        case kVK_UpArrow:
            select(selectedIndex - 1)
        case kVK_PageDown:
            select(selectedIndex + 8)
        case kVK_PageUp:
            select(selectedIndex - 8)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // ⇧: copy only. ⌘: without formatting.
            if let item = selectedItem { choose(item, paste: !shift, keepFormatting: !command) }
        case kVK_Tab:
            // Toggles the full content of the selected item; focus stays in the search box.
            showPreview.toggle()
            updatePreview()
        case kVK_Delete where command:
            // ⌘⌫ removes the selected item, ⇧⌘⌫ clears the history (pinned items stay).
            if shift { history.clear(undoable: true) } else if let item = selectedItem { history.remove(item, undoable: true) }
        case kVK_ForwardDelete where caretAtEnd:
            // ⌦ acts on the list when it would do nothing in the search box, like Delete on Windows.
            if command { history.clear(undoable: true) } else if let item = selectedItem { history.remove(item, undoable: true) }
        default:
            guard command else { return false }
            if let digit = Self.digit(event.keyCode), !mods.contains(.option), !mods.contains(.control) {
                // ⌘1…9 picks the item at that position, like ↩ (with ⇧: copy only).
                if digit <= results.count { choose(results[digit - 1], paste: !shift) }
                return true
            }
            switch (key, shift) {
            case ("z", false) where history.canUndo:
                undo() // brings back removed items; without any, ⌘Z undoes typing in the search box
            case ("p", false):
                if let item = selectedItem { togglePin(item) }
            case (",", false):
                // ⌘, opens Settings, as in every Mac app.
                hide()
                settingsRequested?()
            // Editing shortcuts for the search box, which an app without a menu bar doesn't get by itself.
            case ("a", false): send(#selector(NSText.selectAll(_:)))
            case ("c", false): send(#selector(NSText.copy(_:)))
            case ("x", false): send(#selector(NSText.cut(_:)))
            case ("v", false): send(#selector(NSText.paste(_:)))
            case ("z", false): send(Selector(("undo:")))
            case ("z", true): send(Selector(("redo:")))
            default: return false
            }
        }
        return true
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: panel)
    }

    private var caretAtEnd: Bool {
        guard let editor = fieldEditor else { return true }
        let range = editor.selectedRange()
        return range.length == 0 && range.location == (editor.string as NSString).length
    }

    private static func digit(_ keyCode: UInt16) -> Int? {
        let keys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let keypad = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
                      kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        if let i = keys.firstIndex(of: Int(keyCode)) { return i + 1 }
        if let i = keypad.firstIndex(of: Int(keyCode)) { return i + 1 }
        return nil
    }

    // ---------------------------------------------------------------- screenshots (UI/Screenshots.swift)

    /// Lays the popup out for this search, selection and preview, off-screen and without taking focus, and draws
    /// its content at 2×: everything except the translucent backdrop, which the screenshot tool draws itself.
    func snapshot(search: String, select index: Int, preview: Bool, appearance: NSAppearance) -> NSBitmapImageRep? {
        panel.appearance = appearance
        searchField.placeholderString = Loc.t("popup.search")
        searchField.stringValue = search
        showPreview = preview
        computeAnchor(.centered)
        refresh(preferredIndex: index) // selects, updates the preview and lays out

        panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        tableView.scrollRowToVisible(0)
        panel.displayIfNeeded()
        defer { panel.orderOut(nil) }

        let size = content.bounds.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        appearance.performAsCurrentDrawingAppearance {
            content.cacheDisplay(in: content.bounds, to: rep)
        }
        return rep
    }

    // ---------------------------------------------------------------- layout

    private func buildPanel() {
        panel.delegate = self
        panel.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false

        // The system draws the translucent backdrop, rounded corners and shadow, like DWM does on Windows.
        let backdrop = NSVisualEffectView()
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.maskImage = Self.roundedMask(radius: 12)
        panel.contentView = backdrop

        content.autoresizingMask = [.width, .height]
        content.frame = backdrop.bounds
        backdrop.addSubview(content)

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        searchIcon.contentTintColor = .secondaryLabelColor

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 15)
        searchField.textColor = .labelColor
        searchField.delegate = self
        searchField.cell?.isScrollable = true
        searchField.cell?.wraps = false
        searchField.cell?.usesSingleLineMode = true

        undoHint.font = .systemFont(ofSize: 12)
        undoHint.textColor = .tertiaryLabelColor
        undoHint.isHidden = true

        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.refusesFirstResponder = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none

        copiedLabel.font = .systemFont(ofSize: 12)
        copiedLabel.textColor = .tertiaryLabelColor
        copiedLabel.lineBreakMode = .byTruncatingTail

        previewTextScroll.drawsBackground = false
        previewTextScroll.hasVerticalScroller = true
        previewTextScroll.autohidesScrollers = true
        previewTextScroll.scrollerStyle = .overlay
        previewText.isEditable = false
        previewText.isSelectable = false
        previewText.drawsBackground = false
        previewText.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        previewText.textColor = .secondaryLabelColor
        previewText.textContainerInset = NSSize(width: 6, height: 4)

        previewImageView.imageScaling = .scaleProportionallyDown
        previewImageView.imageAlignment = .alignTopLeft

        previewPane.isHidden = true
        [previewDivider, copiedLabel, previewTextScroll, previewImageView].forEach(previewPane.addSubview)
        [searchIcon, searchField, undoHint, divider, emptyLabel, scrollView, previewPane].forEach(content.addSubview)
    }

    /// Lays out the popup for its current content and resizes it, keeping it at its anchor.
    private func relayout() {
        let width = Self.width
        let previewHeight = previewPane.isHidden ? 0 : Self.previewHeight

        // Search row
        searchIcon.frame = NSRect(x: 18, y: (Self.searchHeight - 18) / 2, width: 18, height: 18)
        undoHint.sizeToFit()
        let hintWidth = undoHint.isHidden ? 0 : undoHint.frame.width + 12
        undoHint.frame = NSRect(x: width - 14 - undoHint.frame.width, y: (Self.searchHeight - undoHint.frame.height) / 2,
                                width: undoHint.frame.width, height: undoHint.frame.height)
        let fieldHeight = searchField.intrinsicContentSize.height
        searchField.frame = NSRect(x: 48, y: (Self.searchHeight - fieldHeight) / 2,
                                   width: width - 48 - 14 - hintWidth, height: fieldHeight)
        divider.frame = NSRect(x: 0, y: Self.searchHeight, width: width, height: 1)

        var y = Self.searchHeight + 1
        let empty = results.isEmpty
        emptyLabel.isHidden = !empty
        scrollView.isHidden = empty
        if empty {
            let labelWidth = width - 36
            let height = emptyLabel.sizeThatFits(NSSize(width: labelWidth, height: .greatestFiniteMagnitude)).height
            emptyLabel.frame = NSRect(x: 18, y: y + 16, width: labelWidth, height: height)
            y += 16 + height + 18
        } else {
            // The preview pane takes its (fixed) height from the list, so a full popup keeps its size.
            let rowsHeight = results.reduce(0) { $0 + ($1.thumbnail != nil ? Self.imageRowHeight : Self.textRowHeight) }
            let listHeight = min(rowsHeight, Self.listMaxHeight - previewHeight)
            scrollView.frame = NSRect(x: 6, y: y + 5, width: width - 12, height: listHeight)
            tableView.tableColumns.first?.width = scrollView.contentSize.width
            y += 5 + listHeight + 6
        }

        if previewHeight > 0 {
            previewPane.frame = NSRect(x: 0, y: y, width: width, height: previewHeight)
            previewDivider.frame = NSRect(x: 0, y: 0, width: width, height: 1)
            copiedLabel.frame = NSRect(x: 18, y: 1 + 6 + 4, width: width - 26, height: 16)
            let bodyY = 1 + 6 + 22.0
            previewTextScroll.frame = NSRect(x: 12, y: bodyY, width: width - 20, height: Self.previewTextHeight)
            previewImageView.frame = NSRect(x: 18, y: bodyY + 4, width: width - 26, height: Self.previewTextHeight - 8)
            y += previewHeight
        }

        panel.setFrame(place(height: ceil(y)), display: true)
        panel.invalidateShadow()
        if !empty, selectedIndex >= 0 { tableView.scrollRowToVisible(selectedIndex) }
    }

    private func computeAnchor(_ placement: PopupPlacement) {
        switch placement {
        case .centered:
            let screen = Self.screenOfFrontWindow() ?? Self.screenWithMouse() ?? NSScreen.main ?? NSScreen.screens[0]
            visibleFrame = screen.visibleFrame
            anchorTop = visibleFrame.maxY - visibleFrame.height / 5
            anchorX = visibleFrame.midX
        case .belowStatusItem(let icon):
            let screen = NSScreen.screens.first { $0.frame.intersects(icon) } ?? NSScreen.main ?? NSScreen.screens[0]
            visibleFrame = screen.visibleFrame
            anchorTop = icon.minY - 6
            anchorX = icon.midX
        }
    }

    /// The frame for a popup of this height: at its anchor, inside the visible part of the screen.
    private func place(height: CGFloat) -> NSRect {
        let margin: CGFloat = 8
        let width = Self.width
        let x = min(max(anchorX - width / 2, visibleFrame.minX + margin), max(visibleFrame.minX + margin, visibleFrame.maxX - width - margin))
        let top = min(anchorTop, visibleFrame.maxY - margin)
        let y = max(top - height, visibleFrame.minY + margin)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// The screen showing most of the frontmost window of the active app.
    private static func screenOfFrontWindow() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
              let primary = NSScreen.screens.first else { return nil }
        // Window bounds have their origin at the top left of the primary screen; Cocoa's at the bottom left.
        let frame = NSRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
        return NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
            .flatMap { area($0.frame.intersection(frame)) > 0 ? $0 : nil }
    }

    private static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private static func area(_ rect: NSRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// ---------------------------------------------------------------- views

/// A view with its origin at the top left, so the layout reads top to bottom like the XAML.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A 1 pt divider line.
final class SeparatorLine: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        bounds.fill()
    }
}

extension NSColor {
    /// A color with separate values for light and dark mode.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    static let pastebirdHover = dynamic(light: NSColor(white: 0, alpha: 0.04), dark: NSColor(white: 1, alpha: 0.06))
    static let pastebirdSelected = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.10))
}

/// A row in the popup: hover and selection backgrounds and the accent pill of the selected item.
final class ClipRowView: NSTableRowView {
    var isCurrent = false { didSet { if oldValue != isCurrent { needsDisplay = true } } }
    private var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            needsDisplay = true
            cell?.isHovered = isHovered
        }
    }

    private var cell: ClipCellView? { subviews.lazy.compactMap { $0 as? ClipCellView }.first }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A reloaded list gets new rows; keep the hover on the row under the mouse.
        guard let window else { return }
        isHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        (subview as? ClipCellView)?.isHovered = isHovered
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isCurrent || isHovered else { return }
        let background = bounds.insetBy(dx: 0, dy: 1)
        (isCurrent ? NSColor.pastebirdSelected : NSColor.pastebirdHover).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        if isCurrent {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: bounds.midY - 8, width: 3, height: 16), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

/// The content of a row: type icon, thumbnail, text, and the remove and pin buttons.
final class ClipCellView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("ClipCell")

    private let icon = NSImageView()
    private let thumbnailView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let removeButton = ClipCellView.makeButton()
    private let pinButton = ClipCellView.makeButton()
    private var isPinned = false

    var onPin: (() -> Void)?
    var onRemove: (() -> Void)?

    var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            updateButtons()
            needsLayout = true
        }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        icon.contentTintColor = .secondaryLabelColor
        thumbnailView.imageScaling = .scaleProportionallyDown
        label.font = .systemFont(ofSize: 14)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true

        removeButton.image = Self.symbol("trash", size: 12)
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        [icon, thumbnailView, label, removeButton, pinButton].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ item: ClipItem, thumbnail: NSImage?) {
        icon.image = Self.symbol(item.symbolName, size: 13)
        thumbnailView.image = thumbnail
        thumbnailView.isHidden = thumbnail == nil
        label.stringValue = item.preview
        isPinned = item.isPinned
        removeButton.toolTip = Loc.t("popup.remove.tooltip")
        pinButton.toolTip = Loc.t("popup.pin.tooltip")
        updateButtons()
        needsLayout = true
    }

    private func updateButtons() {
        pinButton.image = Self.symbol(isPinned ? "pin.fill" : "pin", size: 12)
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .tertiaryLabelColor
        // Pin: always shown for pinned items, on hover for the others. Remove: on hover.
        pinButton.isHidden = !(isPinned || isHovered)
        removeButton.isHidden = !isHovered
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        icon.frame = NSRect(x: 14, y: (h - 16) / 2, width: 16, height: 16)

        var right = bounds.width - 6
        pinButton.frame = NSRect(x: right - 24, y: (h - 22) / 2, width: 24, height: 22)
        right -= 24 // the pin keeps its space, so text doesn't jump when it appears
        if !removeButton.isHidden {
            removeButton.frame = NSRect(x: right - 24, y: (h - 22) / 2, width: 24, height: 22)
            right -= 24
        }
        right -= 4

        var x: CGFloat = 44
        if let image = thumbnailView.image, !thumbnailView.isHidden {
            let scale = min(1, min(32 / max(image.size.height, 1), 128 / max(image.size.width, 1)))
            let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
            thumbnailView.frame = NSRect(x: x, y: (h - size.height) / 2, width: size.width, height: size.height)
            x += size.width + 10
        }
        let labelHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: x, y: (h - labelHeight) / 2, width: max(0, right - x), height: labelHeight)
    }

    @objc private func removeClicked() { onRemove?() }
    @objc private func pinClicked() { onPin?() }

    private static func makeButton() -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.refusesFirstResponder = true
        button.isHidden = true
        return button
    }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }
}
