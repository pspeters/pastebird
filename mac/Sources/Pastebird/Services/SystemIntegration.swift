import AppKit
import ServiceManagement
import UserNotifications

/// Open at login, through the login item macOS manages for the app (System Settings → General → Login Items).
enum AutoStart {
    /// Turns autostart on or off and returns the resulting state.
    static func apply(_ enabled: Bool) -> Bool {
        guard AppInfo.isAppBundle else { return false } // `swift run` during development: nothing to register
        let service = SMAppService.mainApp
        do {
            if enabled && service.status != .enabled {
                try service.register()
            } else if !enabled && service.status == .enabled {
                try service.unregister()
            }
        } catch {
            LocalStorage.log(error)
        }
        return service.status == .enabled
    }

    /// The real state: the user can switch the login item off in System Settings.
    static var isEnabled: Bool { AppInfo.isAppBundle && SMAppService.mainApp.status == .enabled }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Notification Center banners, the counterpart of the tray balloons on Windows. Clicking one runs its action.
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    private var actions: [String: () -> Void] = [:]

    /// UNUserNotificationCenter needs a real app bundle; it crashes under `swift run`.
    private var center: UNUserNotificationCenter? { AppInfo.isAppBundle ? UNUserNotificationCenter.current() : nil }

    override init() {
        super.init()
        center?.delegate = self
        center?.requestAuthorization(options: [.alert]) { _, error in
            if let error { LocalStorage.log(error) }
        }
    }

    func show(_ title: String, _ text: String, onClick: (() -> Void)? = nil) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        let id = UUID().uuidString
        if let onClick { actions[id] = onClick }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { LocalStorage.log(error) }
        }
    }

    // Pastebird is never the active app in the usual sense, so show banners also while it is.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        DispatchQueue.main.async {
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                self.actions[id]?()
            }
            self.actions[id] = nil
            completionHandler()
        }
    }
}
