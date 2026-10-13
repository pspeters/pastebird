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
            button.image = Self.birdImage()
            button.toolTip = Loc.t("tray.tooltip")
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self
    }

    /// The bird from the app icon (tools/IconGen) as a menu bar template: the same shapes on the same 32×32 grid,
    /// in one color that macOS adapts to a light or dark menu bar. The wing and eye are cut out, and a thin gap
    /// separates the sticky note from the beak.
    private static func birdImage() -> NSImage {
        // The bird spans x 3…30 and y 6…28 of the grid; scale that to 18 pt high.
        let scale: CGFloat = 18 / 22
        let image = NSImage(size: NSSize(width: 27 * scale, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -3, y: -6)
            NSColor.black.set()

            func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
            }
            func polygon(_ points: [NSPoint]) -> NSBezierPath {
                let path = NSBezierPath()
                path.move(to: points[0])
                points.dropFirst().forEach(path.line)
                path.close()
                return path
            }

            // Body, head, tail and beak
            ellipse(14.5, 19, 9, 8).fill()
            ellipse(18.5, 13.5, 5.5, 5.5).fill()
            polygon([NSPoint(x: 9.5, y: 16.5), NSPoint(x: 4, y: 11.5), NSPoint(x: 6.5, y: 21.5)]).fill()
            polygon([NSPoint(x: 22.5, y: 11.6), NSPoint(x: 27, y: 13.9), NSPoint(x: 22.5, y: 16.2)]).fill()

            // Sticky note held in the beak, tilted 14°, with a gap around it
            let note = NSBezierPath(roundedRect: NSRect(x: 23.5, y: 15.5, width: 6, height: 7), xRadius: 1, yRadius: 1)
            var tilt = AffineTransform(translationByX: 26.5, byY: 19)
            tilt.rotate(byDegrees: 14)
            tilt.translate(x: -26.5, y: -19)
            note.transform(using: tilt)
            context.setBlendMode(.clear)
            note.lineWidth = 2.4
            note.stroke()
            context.setBlendMode(.normal)
            note.fill()

            // Wing and eye
            context.setBlendMode(.clear)
            let wing = NSBezierPath()
            wing.move(to: NSPoint(x: 8, y: 18))
            wing.curve(to: NSPoint(x: 19, y: 18.5), controlPoint1: NSPoint(x: 11.7, y: 15), controlPoint2: NSPoint(x: 15.3, y: 15.2))
            wing.curve(to: NSPoint(x: 8, y: 18), controlPoint1: NSPoint(x: 15, y: 22.5), controlPoint2: NSPoint(x: 11.3, y: 22.3))
            wing.fill()
            ellipse(20, 12.3, 1.3, 1.3).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pastebird"
        return image
    }

    /// Updates the tooltip after a language change.
    func refreshTexts() {
        item.button?.toolTip = Loc.t("tray.tooltip")
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
