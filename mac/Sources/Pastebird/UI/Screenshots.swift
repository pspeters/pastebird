import AppKit

/// Renders screenshots of the real popup with sample data, so no real clipboard history ends up in them; the Mac
/// counterpart of tools/Screenshots. The popup is laid out off-screen and never activated; the translucent macOS
/// backdrop is drawn here instead.
///   Pastebird --screenshots <folder> [en|nl] [--icon <png>]
/// .github/workflows/mac-screenshots.yml runs it on GitHub Actions.
enum Screenshots {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count else { return false }
        let folder = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        let dutch = args.count > i + 2 && args[i + 2] == "nl"
        let icon = args.firstIndex(of: "--icon").flatMap { $0 + 1 < args.count ? NSImage(contentsOfFile: args[$0 + 1]) : nil }

        Loc.shared.apply(dutch ? "nl" : "en")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Renderer(folder: folder, dutch: dutch, logo: icon ?? NSApp.applicationIconImage).renderAll()
        return true
    }
}

private struct Renderer {
    // Canvas in points, rendered at 2×: 1920 × 1080 PNGs, the same as the Windows screenshots.
    static let width: CGFloat = 960, height: CGFloat = 540

    let folder: URL
    let dutch: Bool
    let logo: NSImage

    private func t(_ en: String, _ nl: String) -> String { dutch ? nl : en }

    func renderAll() {
        shot("1-history", dark: false, search: "", select: 0, preview: false,
             t("Your clipboard,\nwith a memory.", "Je klembord,\nmet geheugen."),
             t("Press ⇧⌘V to see everything you copied: text, links, files and screenshots.",
               "Druk op ⇧⌘V en zie alles wat je kopieerde: tekst, links, bestanden en screenshots."))
        shot("2-search", dark: false, search: "proj", select: 0, preview: false,
             t("Find it in a\nfew keystrokes.", "Gevonden in een\npaar toetsaanslagen."),
             t("Fuzzy search: type \"proj\" and your project files show up. Press Return to paste.",
               "Slim zoeken: typ \"proj\" en je projectbestanden verschijnen. Return plakt het."))
        shot("3-preview", dark: false, search: "", select: 6, preview: true,
             t("See the\nwhole item.", "Bekijk het\nhele item."),
             t("Press Tab to preview long or multi-line text, and see when you copied it.",
               "Druk op Tab voor de volledige inhoud van lange tekst, en zie wanneer je het kopieerde."))
        shot("4-dark", dark: true, search: "", select: 4, preview: false,
             t("Pin what you\nuse often.", "Pin wat je\nvaak gebruikt."),
             t("Pinned items stay at the top. Light and dark mode, just like macOS. Everything stays on your Mac.",
               "Vastgepinde items blijven bovenaan. Licht en donker, net als macOS. Alles blijft op je Mac."))
    }

    private func shot(_ name: String, dark: Bool, search: String, select: Int, preview: Bool, _ title: String, _ text: String) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let popup = PopupWindow(history: ClipboardHistory(items: sampleItems(), maxItems: 200), storage: LocalStorage(useKeychain: false))
        guard let content = popup.snapshot(search: search, select: select, preview: preview, appearance: appearance),
              let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(Self.width * 2), pixelsHigh: Int(Self.height * 2),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: canvas) else {
            print("Couldn't render \(name)")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        // Points at 2×, with the origin at the top left, so the layout reads like the Windows tool.
        context.cgContext.translateBy(x: 0, y: Self.height * 2)
        context.cgContext.scaleBy(x: 2, y: -2)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        appearance.performAsCurrentDrawingAppearance {
            draw(content: content, dark: dark, title: title, text: text)
        }
        NSGraphicsContext.restoreGraphicsState()
        canvas.size = NSSize(width: Self.width, height: Self.height) // 144 dpi, so it shows at its size in points

        let url = folder.appendingPathComponent("pastebird-mac-\(name).png")
        try? canvas.representation(using: .png, properties: [:])?.write(to: url)
        print(url.path)
    }

    private func draw(content: NSBitmapImageRep, dark: Bool, title: String, text: String) {
        let bounds = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let backdrop = dark
            ? NSGradient(colorsAndLocations: (rgb(0x0B, 0x12, 0x20), 0), (rgb(0x10, 0x23, 0x4A), 0.6), (rgb(0x1D, 0x4E, 0xD8), 1))
            : NSGradient(colorsAndLocations: (rgb(0xF7, 0xFA, 0xFD), 0), (rgb(0xDB, 0xEA, 0xFE), 0.55), (rgb(0x93, 0xC5, 0xFD), 1))
        backdrop?.draw(in: bounds, angle: atan2(Self.height, Self.width) * 180 / .pi) // top left to bottom right

        // Caption: logo, title and text, centered vertically on the left.
        let ink = dark ? rgb(0xE8, 0xEE, 0xF8) : rgb(0x0F, 0x17, 0x2A)
        let muted = dark ? rgb(0xA9, 0xB6, 0xCC) : rgb(0x47, 0x55, 0x69)
        let captionWidth: CGFloat = 330
        // Every line of the title on one line: a smaller font for a long word ("toetsaanslagen").
        let titleLines = title.components(separatedBy: "\n")
        func titleFits(_ size: CGFloat) -> Bool {
            let font = NSFont.systemFont(ofSize: size, weight: .bold)
            return titleLines.allSatisfy { NSAttributedString(string: $0, attributes: [.font: font]).size().width <= captionWidth }
        }
        var titleSize: CGFloat = 38
        while titleSize > 28 && !titleFits(titleSize) { titleSize -= 1 }
        let titleText = styled(title, font: .systemFont(ofSize: titleSize, weight: .bold), lineHeight: titleSize + 6, color: ink)
        let bodyText = styled(text, font: .systemFont(ofSize: 16), lineHeight: 24, color: muted)
        let titleHeight = ceil(titleText.boundingRect(with: NSSize(width: captionWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin).height)
        let bodyHeight = ceil(bodyText.boundingRect(with: NSSize(width: captionWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin).height)
        var y = (Self.height - (52 + 18 + titleHeight + 16 + bodyHeight)) / 2
        logo.draw(in: NSRect(x: 48, y: y, width: 52, height: 52), from: .zero, operation: .sourceOver, fraction: 1,
                  respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        y += 52 + 18
        titleText.draw(with: NSRect(x: 48, y: y, width: captionWidth, height: titleHeight), options: .usesLineFragmentOrigin)
        y += titleHeight + 16
        bodyText.draw(with: NSRect(x: 48, y: y, width: captionWidth, height: bodyHeight), options: .usesLineFragmentOrigin)

        // The popup on a macOS style surface: rounded corners, hairline border, soft shadow.
        let size = content.size
        let frame = NSRect(x: Self.width - 48 - size.width, y: (Self.height - size.height) / 2, width: size.width, height: size.height)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 48
        shadow.shadowOffset = NSSize(width: 0, height: -12) // shadow offsets ignore the flipped coordinates: this is down
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.22)
        shadow.set()
        (dark ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 0.97) : NSColor(srgbRed: 0.975, green: 0.975, blue: 0.98, alpha: 0.97)).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        content.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()

        (dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.10)).setStroke()
        let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 11.5, yRadius: 11.5)
        border.lineWidth = 1
        border.stroke()
    }

    private func styled(_ text: String, font: NSFont, lineHeight: CGFloat, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    // ---------------------------------------------------------------- sample data

    private func sampleItems() -> [ClipItem] {
        let now = Date()
        func item(_ content: String, _ kind: ClipKind, _ minutesAgo: Double, pinned: Bool = false) -> ClipItem {
            let item = ClipItem(content: content, kind: kind)
            item.copiedAt = now.addingTimeInterval(-minutesAgo * 60)
            item.isPinned = pinned
            return item
        }

        let screenshot = ClipItem(imageHash: "sample-screenshot", width: 1920, height: 1080, thumbnail: fakeScreenshot())
        screenshot.copiedAt = now.addingTimeInterval(-9 * 60)
        screenshot.imageText = t("Q3 revenue dashboard · Sales by region · Europe 42%", "Omzet Q3 · Verkoop per regio · Europa 42%")

        return [
            item(t("Kind regards,\nAlex Morgan\nProduct Designer, Northwind", "Met vriendelijke groet,\nAlex Morgan\nProductontwerper, Northwind"), .text, 4000, pinned: true),
            item(t("42 Harbour Lane, Brighton BN1 4AB", "Havenstraat 42, 1011 AB Amsterdam"), .text, 9000, pinned: true),
            item("https://github.com/pspeters/pastebird", .url, 1),
            item("/Users/alex/Projects/website/index.php", .filePath, 3),
            screenshot,
            item(t("Meeting moved to Thursday 10:00, room 4.12", "Overleg verplaatst naar donderdag 10:00, zaal 4.12"), .text, 10),
            item("git checkout -b feature/search\ngit commit -am \"Add fuzzy search\"\ngit push -u origin feature/search", .text, 12),
            item(t("/Users/alex/Pictures/logo.png\n/Users/alex/Documents/report.pdf\n/Users/alex/Documents/notes.txt",
                   "/Users/alex/Pictures/logo.png\n/Users/alex/Documents/rapport.pdf\n/Users/alex/Documents/notities.txt"), .files, 26),
            item("/Users/alex/Projects/api/main.swift", .filePath, 40),
            item(t("Thanks! I'll send the invoice before Friday.", "Bedankt! Ik stuur de factuur voor vrijdag."), .text, 55),
            item("https://developer.apple.com/macos/", .url, 70),
            item("SELECT name, email FROM customers WHERE active = 1 ORDER BY name;", .text, 95),
            item(t("Kickoff notes: scope, timeline and budget", "Notities kick-off: scope, planning en budget"), .text, 130),
        ]
    }

    /// A small thumbnail that looks like a screenshot of a dashboard, stored at 2× like real thumbnails.
    private func fakeScreenshot() -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 228, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.translateBy(x: 0, y: 128)
        context.cgContext.scaleBy(x: 2, y: -2)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        rgb(0xF8, 0xFA, 0xFC).setFill()
        NSRect(x: 0, y: 0, width: 114, height: 64).fill()
        rgb(0x25, 0x63, 0xEB).setFill()
        NSRect(x: 0, y: 0, width: 114, height: 10).fill()
        rgb(0x60, 0xA5, 0xFA).setFill()
        for (i, bar) in [18.0, 30, 24, 40, 34, 46].enumerated() {
            NSRect(x: 8 + CGFloat(i) * 11, y: 58 - bar, width: 7, height: bar).fill()
        }
        rgb(0xF5, 0x9E, 0x0B).setFill()
        NSBezierPath(ovalIn: NSRect(x: 81, y: 25, width: 26, height: 26)).fill()
        rgb(0xF8, 0xFA, 0xFC).setFill()
        NSBezierPath(ovalIn: NSRect(x: 88, y: 32, width: 12, height: 12)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
