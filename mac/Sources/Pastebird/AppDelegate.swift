import AppKit

/// Pastebird has no main window: the app lives in the menu bar, watches the clipboard and opens the
/// popup on the global shortcut. This class wires the services together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showNotification = Notification.Name("app.pastebird.Pastebird.show")

    private(set) var settings = AppSettings()
    private var storage: LocalStorage!
    private var history: ClipboardHistory!
    private var monitor: ClipboardMonitor?
    private var hotkey: GlobalHotkeyService?
    private var statusItem: StatusItemService?
    private var popup: PopupWindow?
    private var settingsWindow: HostingWindow?
    private var settingsModel: SettingsModel?
    private var whatsNewWindow: HostingWindow?
    private var updates: UpdateService?
    private var notifications: Notifications?
    private var saveTimer: Timer?
    private var expireTimer: Timer?
    private let recognitionQueue = DispatchQueue(label: "Pastebird.recognition", qos: .utility)
    private var pasteTarget: NSRunningApplication?
    private var hotkeySuspended = false
    private var askedForPastePermission = false

    /// Called when a newer version is found, so an open Settings window can show it.
    var updateStateChanged: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one Pastebird per user; starting it again just opens the popup of the one that runs.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if AppInfo.isAppBundle && !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(Self.showNotification, object: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        storage = LocalStorage()
        let firstRun = !storage.settingsExist
        settings = storage.loadSettings()
        Loc.shared.apply(settings.language)
        NSApp.mainMenu = Self.makeMainMenu()

        history = ClipboardHistory(items: storage.loadHistory(), maxItems: settings.maxItems)

        // Save shortly after changes instead of on every copy.
        history.observe { [weak self] in
            guard let self else { return }
            self.saveTimer?.invalidate()
            self.saveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.saveHistoryNow() }
        }

        // Items older than the chosen number of days go: at start and then hourly.
        removeExpiredItems()
        expireTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.removeExpiredItems() }

        notifications = Notifications()

        monitor = ClipboardMonitor()
        monitor?.captured = { [weak self] item, data in self?.onCaptured(item, data) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.recognizeMissingText() }

        popup = PopupWindow(history: history, storage: storage)
        popup?.itemChosen = { [weak self] item, paste, keepFormatting in self?.onItemChosen(item, paste: paste, keepFormatting: keepFormatting) }
        popup?.settingsRequested = { [weak self] in self?.showSettings() }

        hotkey = GlobalHotkeyService()
        hotkey?.pressed = { [weak self] in self?.onHotkeyPressed() }
        let hotkeyRegistered = hotkey?.register(settings.hotkey) ?? false

        statusItem = StatusItemService()
        statusItem?.openRequested = { [weak self] in self?.onStatusItemOpen() }
        statusItem?.clearRequested = { [weak self] in self?.clearHistory() }
        statusItem?.settingsRequested = { [weak self] in self?.showSettings() }
        statusItem?.exitRequested = { NSApp.terminate(nil) }

        if UpdateService.isSupported {
            let updates = UpdateService()
            updates.updateFound = { [weak self] in self?.onUpdateFound($0) }
            statusItem?.updateRequested = { [weak self] in Task { await self?.installUpdate() } }
            updates.enabled = settings.checkForUpdates
            self.updates = updates
        }

        syncAutoStart()

        // Just updated? Offer "What's new".
        let previousVersion = AppVersion(settings.lastRunVersion)
        let updated = !firstRun && (previousVersion == nil || previousVersion! < AppVersion.current)
        if settings.lastRunVersion != AppInfo.version {
            settings.lastRunVersion = AppInfo.version
            storage.saveSettings(settings)
        }

        if updated {
            notifications?.show(Loc.t("notify.updated.title", AppInfo.version), Loc.t("notify.updated.text")) { [weak self] in
                self?.showWhatsNew(since: previousVersion, afterUpdate: true)
            }
        }
        if firstRun {
            storage.saveSettings(settings)
            notifications?.show(Loc.t("notify.running.title"), Loc.t("notify.running.text", settings.hotkey.description))
            // Pasting into other apps needs the Accessibility permission; ask right away rather than at the first paste.
            if settings.pasteAutomatically && !PasteService.isTrusted {
                askedForPastePermission = true
                PasteService.requestPermission()
            }
        }
        if !hotkeyRegistered {
            notifications?.show(Loc.t("notify.hotkey.title"), Loc.t("notify.hotkey.text", settings.hotkey.description))
        }

        DistributedNotificationCenter.default().addObserver(forName: Self.showNotification, object: nil, queue: .main) { [weak self] _ in
            self?.openPopup(.centered, allowPaste: false)
        }
    }

    /// Opening Pastebird from Finder or Spotlight while it runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPopup(.centered, allowPaste: false)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if history != nil { saveHistoryNow() }
        monitor?.stop()
        hotkey?.unregister()
    }

    // ---------------------------------------------------------------- popup

    private func onHotkeyPressed() {
        guard let popup else { return }
        if popup.isVisible {
            popup.hide() // the shortcut toggles
        } else {
            openPopup(.centered, allowPaste: true)
        }
    }

    private func onStatusItemOpen() {
        guard let popup else { return }
        // Clicking the icon while the popup is open closes it.
        if popup.isVisible { popup.hide(); return }
        if popup.wasJustHidden { return }
        if let frame = statusItem?.buttonFrame {
            openPopup(.belowStatusItem(frame), allowPaste: false)
        } else {
            openPopup(.centered, allowPaste: false)
        }
    }

    private func openPopup(_ placement: PopupPlacement, allowPaste: Bool) {
        pasteTarget = allowPaste ? PasteService.captureTarget() : nil
        popup?.show(placement)
    }

    private func onCaptured(_ copied: ClipItem, _ data: ClipData?) {
        let item = history.add(copied)
        storage.saveData(item, data)
        if item.kind == .image && item.imageText == nil {
            recognizeText(item)
        }
    }

    /// Reads the text in an image in the background, one image at a time, so it can be found by searching.
    private func recognizeText(_ item: ClipItem) {
        guard let png = storage.loadData(item)?.png else { return }
        recognitionQueue.async { [weak self] in
            guard let text = TextRecognition.recognize(png) else { return }
            DispatchQueue.main.async { self?.history.setImageText(item, text) }
        }
    }

    /// Recognizes the text in images that don't have it yet.
    private func recognizeMissingText() {
        history.items.filter { $0.kind == .image && $0.imageText == nil }.forEach(recognizeText)
    }

    private func onItemChosen(_ item: ClipItem, paste: Bool, keepFormatting: Bool) {
        do {
            try monitor?.setClipboard(item, stored: storage.loadData(item), keepFormatting: keepFormatting)
        } catch {
            LocalStorage.log(error)
            return // the image is missing; nothing to paste
        }

        history.promote(item)

        if paste && settings.pasteAutomatically, let target = pasteTarget {
            if PasteService.isTrusted {
                PasteService.paste(into: target)
            } else if !askedForPastePermission {
                // Once per session: explain why nothing was pasted and lead the way to the permission.
                askedForPastePermission = true
                notifications?.show(Loc.t("notify.paste.title"), Loc.t("notify.paste.text")) {
                    PasteService.openAccessibilitySettings()
                }
                PasteService.requestPermission()
            }
        }
        pasteTarget = nil
    }

    // ---------------------------------------------------------------- settings (used by SettingsWindow)

    private func showSettings() {
        if settingsWindow == nil {
            let model = SettingsModel(app: self)
            let window = HostingWindow(titleKey: "settings.title", rootView: SettingsView(model: model))
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.settingsWindow = nil
                self?.settingsModel = nil
                self?.updateStateChanged = nil
                self?.resumeHotkey()
            }
            settingsWindow = window
            settingsModel = model
        }
        settingsWindow?.present()
    }

    /// Applies the autostart setting and returns the state that actually took effect.
    func setAutoStart(_ enabled: Bool) -> Bool {
        let actual = AutoStart.apply(enabled)
        // macOS may need the user's approval first; remember the wish, so it applies once approved.
        settings.startAtLogin = enabled
        storage.saveSettings(settings)
        return actual
    }

    /// Registers the login item (again) at every start, so it points to this copy of Pastebird. Registering doesn't
    /// override the user: when they switched it off in System Settings, it stays off until they approve it there.
    private func syncAutoStart() {
        _ = AutoStart.apply(settings.startAtLogin)
    }

    func setAutoPaste(_ enabled: Bool) {
        settings.pasteAutomatically = enabled
        storage.saveSettings(settings)
    }

    func setLanguage(_ language: AppLanguage) {
        settings.language = language
        storage.saveSettings(settings)
        Loc.shared.apply(language)
        history.items.forEach { $0.resetCachedTexts() }
        statusItem?.refreshTexts()
    }

    func setMaxItems(_ maxItems: Int) {
        settings.maxItems = maxItems
        storage.saveSettings(settings)
        history.maxItems = maxItems
    }

    func setKeepDays(_ days: Int) {
        settings.keepDays = days
        storage.saveSettings(settings)
        removeExpiredItems()
    }

    private func removeExpiredItems() {
        if settings.keepDays > 0 {
            history.removeCopied(before: Date().addingTimeInterval(-Double(settings.keepDays) * 24 * 60 * 60))
        }
    }

    /// Checks that the shortcut is free and stores it. It becomes active once editing ends.
    func trySetHotkey(_ hotkey: Hotkey) -> Bool {
        guard let service = self.hotkey, service.register(hotkey) else { return false }
        if hotkeySuspended { service.unregister() }
        settings.hotkey = hotkey
        storage.saveSettings(settings)
        return true
    }

    func suspendHotkey() {
        hotkeySuspended = true
        hotkey?.unregister()
    }

    func resumeHotkey() {
        guard hotkeySuspended else { return }
        hotkeySuspended = false
        hotkey?.register(settings.hotkey)
    }

    func clearHistory() {
        guard history.hasUnpinnedItems else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = Loc.t("clear.confirm")
        alert.informativeText = Loc.t("clear.confirm.detail")
        alert.alertStyle = .warning
        alert.addButton(withTitle: Loc.t("clear.confirm.yes")).hasDestructiveAction = true
        alert.addButton(withTitle: Loc.t("clear.confirm.no")).keyEquivalent = "\u{1b}"
        if alert.runModal() == .alertFirstButtonReturn {
            history.clear()
        }
    }

    // ---------------------------------------------------------------- what's new

    /// Shows the changelog entries since `since` (all entries when nil or nothing is newer).
    func showWhatsNew(since: AppVersion? = nil, afterUpdate: Bool = false) {
        whatsNewWindow?.close()
        var releases = Changelog.between(since, AppVersion.current)
        if releases.isEmpty { releases = Changelog.load() }
        let view = WhatsNewView(releases: releases, afterUpdate: afterUpdate) { [weak self] in self?.whatsNewWindow?.close() }
        let window = HostingWindow(titleKey: "whatsnew.title", rootView: view)
        whatsNewWindow = window
        window.present()
    }

    // ---------------------------------------------------------------- updates

    var updatesSupported: Bool { updates != nil }

    var availableUpdate: UpdateInfo? { updates?.available }

    func setCheckForUpdates(_ enabled: Bool) {
        settings.checkForUpdates = enabled
        storage.saveSettings(settings)
        updates?.enabled = enabled
    }

    /// Checks right away (from Settings). Returns false when GitHub couldn't be reached.
    @MainActor
    func checkForUpdates() async -> Bool {
        await updates?.check() ?? false
    }

    private func onUpdateFound(_ update: UpdateInfo) {
        statusItem?.updateVersion = update.version.description
        notifications?.show(Loc.t("notify.update.title"), Loc.t("notify.update.text", update.version)) { [weak self] in
            Task { await self?.installUpdate() }
        }
        updateStateChanged?()
    }

    /// Downloads the update and quits, so the new version can take Pastebird's place and start.
    @MainActor
    func installUpdate() async {
        guard let updates, let update = updates.available else { return }
        notifications?.show(Loc.t("notify.updating.title"), Loc.t("notify.updating.text"))
        if await updates.downloadAndInstall(update) {
            NSApp.terminate(nil)
            return
        }
        notifications?.show(Loc.t("notify.updatefailed.title"), Loc.t("notify.updatefailed.text")) {
            AppDelegate.openUrl(AppInfo.releasesUrl)
        }
    }

    static func openUrl(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    // ---------------------------------------------------------------- lifetime

    private func saveHistoryNow() {
        saveTimer?.invalidate()
        saveTimer = nil
        storage.saveHistory(history.items, removedButUndoable: history.recentlyRemoved)
    }

    /// Pastebird has no menu bar of its own, but the standard editing shortcuts and ⌘W go through a main menu.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: Loc.t("tray.exit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}
