import AppKit

/// The menu bar icon, the counterpart of the tray icon on Windows: a click opens the popup below it,
/// a right-click (or ⌃-click) shows the menu.
final class StatusItemService: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    var openRequested: (() -> Void)?
    var clearRequested: (() -> Void)?
    var settingsRequested: (() -> Void)?
    var exitRequested: (() -> Void)?
    var updateRequested: (() -> Void)?

    /// Version shown in the "update" menu item, or nil to hide it.
    var updateVersion: String?

    override init() {
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "Pastebird")
                ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastebird")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Pastebird"
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self
    }

    /// The icon's frame on screen, to place the popup below it.
    var buttonFrame: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            openRequested?()
        }
    }

    private func showMenu() {
        menu.removeAllItems()
        add(Loc.t("tray.open"), #selector(open))
        add(Loc.t("tray.clear"), #selector(clear))
        add(Loc.t("tray.settings"), #selector(settings), key: ",")
        if let updateVersion { add(Loc.t("tray.update", updateVersion), #selector(update)) }
        menu.addItem(.separator())
        add(Loc.t("tray.exit"), #selector(exit), key: "q")

        // Attaching the menu for one click shows it the way macOS shows menu bar menus.
        item.menu = menu
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        item.menu = nil // the next left-click opens the popup again
    }

    private func add(_ title: String, _ action: Selector, key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
    }

    @objc private func open() { openRequested?() }
    @objc private func clear() { clearRequested?() }
    @objc private func settings() { settingsRequested?() }
    @objc private func update() { updateRequested?() }
    @objc private func exit() { exitRequested?() }
}
