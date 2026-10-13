import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, also when started without the app bundle (swift run)

// `Pastebird --screenshots <folder> [en|nl]` renders the screenshots and quits (UI/Screenshots.swift).
if Screenshots.runIfRequested() { exit(0) }

let delegate = AppDelegate()
app.delegate = delegate
app.run()
