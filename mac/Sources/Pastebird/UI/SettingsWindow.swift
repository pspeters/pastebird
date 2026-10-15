import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// A titled window for a SwiftUI view. Esc closes it, like on Windows.
final class HostingWindow: NSWindow {
    private var titleKey = ""
    private var languageObserver: AnyCancellable?

    convenience init<Content: View>(titleKey: String, rootView: Content) {
        self.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let controller = NSHostingController(rootView: rootView)
        contentViewController = controller
        setContentSize(controller.view.fittingSize)
        isReleasedWhenClosed = false
        self.titleKey = titleKey
        title = Loc.t(titleKey)
        languageObserver = Loc.shared.$code.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self.map { $0.title = Loc.t($0.titleKey) } }
        }
        center()
    }

    override func cancelOperation(_ sender: Any?) { close() }

    /// Shows the window in front, also while Pastebird isn't the active app.
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

/// The state of the settings window. Every change applies and saves immediately.
final class SettingsModel: ObservableObject {
    private unowned let app: AppDelegate
    private var observers: Set<AnyCancellable> = []

    @Published var autoStartHintKey = "settings.autostart.desc"
    @Published var hotkeyHint = ""
    @Published var isRecordingHotkey = false
    @Published var updateStatusKey = ""
    @Published var isUpdating = false
    @Published var isTrusted = PasteService.isTrusted

    init(app: AppDelegate) {
        self.app = app
        app.updateStateChanged = { [weak self] in self?.objectWillChange.send() }
        // The Accessibility permission is granted in System Settings; notice it when the user comes back.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .merge(with: Timer.publish(every: 2, on: .main, in: .common).autoconnect().map { _ in Notification(name: .init("tick")) })
            .sink { [weak self] _ in
                guard let self, self.isTrusted != PasteService.isTrusted else { return }
                self.isTrusted = PasteService.isTrusted
            }
            .store(in: &observers)
        if app.settings.startAtLogin && !AutoStart.isEnabled && AppInfo.isAppBundle {
            autoStartHintKey = "settings.autostart.denied"
        }
    }

    var settings: AppSettings { app.settings }

    var autoStart: Bool {
        get { app.settings.startAtLogin }
        set {
            let actual = app.setAutoStart(newValue)
            autoStartHintKey = newValue && !actual ? "settings.autostart.denied" : "settings.autostart.desc"
            objectWillChange.send()
        }
    }

    var autoPaste: Bool {
        get { app.settings.pasteAutomatically }
        set {
            app.setAutoPaste(newValue)
            if newValue && !PasteService.isTrusted { PasteService.requestPermission() }
            objectWillChange.send()
        }
    }

    var maxItems: Int {
        get { app.settings.maxItems }
        set { app.setMaxItems(newValue); objectWillChange.send() }
    }

    var keepDays: Int {
        get { app.settings.keepDays }
        set { app.setKeepDays(newValue); objectWillChange.send() }
    }

    /// Code of the chosen language, or "" for the system default (also for a language that is gone).
    var language: String {
        get { Loc.languages.first { $0.code == app.settings.language }?.code ?? "" }
        set { app.setLanguage(newValue.isEmpty ? nil : newValue); objectWillChange.send() }
    }

    var checkForUpdates: Bool {
        get { app.settings.checkForUpdates }
        set { app.setCheckForUpdates(newValue); objectWillChange.send() }
    }

    var updatesSupported: Bool { app.updatesSupported }

    var updateStatus: String {
        if let update = app.availableUpdate { return Loc.t("settings.updates.available", update.version) }
        return updateStatusKey.isEmpty ? Loc.t("about.version", AppInfo.version) : Loc.t(updateStatusKey)
    }

    var updateButtonTitle: String { Loc.t(app.availableUpdate != nil ? "settings.updates.install" : "settings.updates.check") }

    @MainActor
    func updateButtonClicked() async {
        isUpdating = true
        defer { isUpdating = false }
        if app.availableUpdate != nil {
            updateStatusKey = "settings.updates.installing"
            await app.installUpdate() // quits Pastebird when the update is ready
            updateStatusKey = "settings.updates.failed"
        } else {
            updateStatusKey = "settings.updates.checking"
            let reached = await app.checkForUpdates()
            updateStatusKey = !reached ? "settings.updates.offline" : app.availableUpdate == nil ? "settings.updates.current" : ""
        }
    }

    var hotkeyText: String { isRecordingHotkey ? Loc.t("settings.hotkey.press") : app.settings.hotkey.description }

    func beginRecording() {
        app.suspendHotkey() // otherwise the current shortcut would open the popup instead
        isRecordingHotkey = true
    }

    func endRecording() {
        app.resumeHotkey()
        isRecordingHotkey = false
    }

    /// Handles a key press while recording; returns true when the shortcut was set.
    func record(_ event: NSEvent) -> Bool {
        let hotkey = Hotkey(event: event)
        if !hotkey.isValid {
            hotkeyHint = Loc.t("settings.hotkey.modifier")
            return false
        }
        if app.trySetHotkey(hotkey) {
            hotkeyHint = ""
            return true
        }
        hotkeyHint = Loc.t("settings.hotkey.taken", hotkey.description)
        return false
    }

    func clearHistory() { app.clearHistory() }
    func showWhatsNew() { app.showWhatsNew() }
    func open(_ url: String) { AppDelegate.openUrl(url) }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Loc.shared

    var body: some View {
        Form {
            Section {
                row("settings.autostart", loc[model.autoStartHintKey]) {
                    Toggle("", isOn: Binding(get: { model.autoStart }, set: { model.autoStart = $0 }))
                        .labelsHidden()
                }
                row("settings.autopaste", loc["settings.autopaste.desc"]) {
                    Toggle("", isOn: Binding(get: { model.autoPaste }, set: { model.autoPaste = $0 }))
                        .labelsHidden()
                }
                if model.autoPaste && !model.isTrusted {
                    HStack(alignment: .firstTextBaseline) {
                        Label(loc["settings.autopaste.permission"], systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(loc["settings.autopaste.open"]) { PasteService.openAccessibilitySettings() }
                    }
                }
                row("settings.hotkey", model.hotkeyHint.isEmpty ? loc["settings.hotkey.desc"] : model.hotkeyHint) {
                    HotkeyField(text: model.hotkeyText,
                                onBegin: model.beginRecording, onEnd: model.endRecording, onKey: model.record)
                        .frame(width: 170, height: 24)
                }
                row("settings.history", loc["settings.history.desc"]) {
                    picker(Binding(get: { model.maxItems }, set: { model.maxItems = $0 }), AppSettings.historySizes) {
                        Loc.t("settings.history.items", $0)
                    }
                }
                row("settings.keep", loc["settings.keep.desc"]) {
                    picker(Binding(get: { model.keepDays }, set: { model.keepDays = $0 }), AppSettings.keepDayChoices) {
                        $0 == 0 ? Loc.t("settings.keep.always") : $0 == 1 ? Loc.t("settings.keep.day") : Loc.t("settings.keep.days", $0)
                    }
                }
                row("settings.language", loc["settings.language.desc"]) {
                    picker(Binding(get: { model.language }, set: { model.language = $0 }), [""] + Loc.languages.map(\.code)) { code in
                        Loc.languages.first { $0.code == code }?.name ?? Loc.t("settings.language.system")
                    }
                }
            }

            if model.updatesSupported {
                Section {
                    row("settings.updates", loc["settings.updates.desc"]) {
                        Toggle("", isOn: Binding(get: { model.checkForUpdates }, set: { model.checkForUpdates = $0 }))
                            .labelsHidden()
                    }
                    HStack {
                        Text(model.updateStatus).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.updateButtonTitle) { Task { await model.updateButtonClicked() } }
                            .disabled(model.isUpdating)
                    }
                }
            }

            Section {
                row("settings.clear", loc["settings.clear.desc"]) {
                    Button(loc["settings.clear.button"]) { model.clearHistory() }
                }
            }

            Section(loc["about.title"]) {
                HStack(alignment: .top, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pastebird").font(.headline)
                        Group {
                            Text("\(Loc.t("about.version", AppInfo.version)) · \(loc["about.license"])")
                            Text(loc["about.createdBy"])
                            Text(loc["about.local"])
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("☕ " + loc["about.donate"]) { model.open(AppInfo.donateUrl) }
                                .buttonStyle(.borderedProminent)
                            Button(loc["about.whatsnew"]) { model.showWhatsNew() }
                            Button(loc["about.github"]) { model.open(AppInfo.gitHubUrl) }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 680)
    }

    private func row<Control: View>(_ titleKey: String, _ description: String, @ViewBuilder control: () -> Control) -> some View {
        LabeledContent {
            control()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc[titleKey])
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 12)
        }
        .toggleStyle(.switch)
    }

    private func picker<Value: Hashable>(_ selection: Binding<Value>, _ values: [Value], label: @escaping (Value) -> String) -> some View {
        Picker("", selection: selection) {
            ForEach(values, id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .frame(width: 170)
    }
}

/// The shortcut box: click it and press a combination.
struct HotkeyField: NSViewRepresentable {
    var text: String
    var onBegin: () -> Void
    var onEnd: () -> Void
    var onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> HotkeyRecorderView { HotkeyRecorderView() }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.text = text
        view.onBegin = onBegin
        view.onEnd = onEnd
        view.onKey = onKey
    }
}

final class HotkeyRecorderView: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 24) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        needsDisplay = true
        onBegin?()
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        onEnd?()
        return true
    }

    override func keyDown(with event: NSEvent) { handle(event) }

    // ⌘-combinations arrive as key equivalents, not as keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        handle(event)
        return true
    }

    private func handle(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if Int(event.keyCode) == kVK_Tab && mods.isSubset(of: [.shift]) {
            if mods.isEmpty { window?.selectNextKeyView(nil) } else { window?.selectPreviousKeyView(nil) } // allow keyboard navigation away
            return
        }
        if Int(event.keyCode) == kVK_Escape && mods.isEmpty {
            window?.makeFirstResponder(nil) // cancel
            return
        }
        if onKey?(event) == true {
            window?.makeFirstResponder(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}
