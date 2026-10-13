import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Remembers which app was active before Pastebird opened and sends ⌘V to it after a choice.
/// Pasting is skipped (the item simply stays on the clipboard) whenever it cannot be done safely.
/// Sending keystrokes needs the Accessibility permission (System Settings → Privacy & Security → Accessibility).
enum PasteService {
    /// The frontmost app if it is a sensible paste target, otherwise nil.
    static func captureTarget() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system dialog that leads to the Accessibility settings (only when Pastebird isn't allowed yet).
    @discardableResult
    static func requestPermission() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func paste(into target: NSRunningApplication) {
        guard !target.isTerminated else { return }
        if NSWorkspace.shared.frontmostApplication != target {
            target.activate(options: [])
        }

        // Wait until the target is active and the user has released ⌘/⇧/⌥/⌃ (⌘1…9 in the popup keeps ⌘ down).
        var attempts = 0
        func attempt() {
            let ready = NSWorkspace.shared.frontmostApplication == target && !modifiersDown()
            if !ready && attempts < 75 {
                attempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: attempt)
                return
            }
            guard ready else { return }
            // Let the target restore focus to its text field.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { sendCommandV() }
        }
        attempt()
    }

    private static func modifiersDown() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return !flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]).isEmpty
    }

    private static func sendCommandV() {
        let v = CGKeyCode(KeyboardLayout.keyCode(typing: "v", fallback: UInt16(kVK_ANSI_V)))
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
