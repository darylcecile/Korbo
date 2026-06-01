import Foundation
import UserNotifications
import UIKit

/// Thin wrapper over `UNUserNotificationCenter` for the handful of local
/// notifications Korbo posts: a backgrounded run needs your attention
/// (permission / question), or it finished / failed while you were away.
///
/// Notifications are suppressed while the app is in the foreground — if you're
/// already looking at the screen the inline cards are enough — unless `force`
/// is set. There is no remote/push component; everything is local and fired
/// straight off the event stream the store already consumes.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private(set) var authorized = false
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    /// Ask for permission once, lazily. Safe to call on every launch — it only
    /// prompts when the status is still `.notDetermined`.
    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    Task { @MainActor in self.authorized = granted }
                }
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in self.authorized = true }
            default:
                Task { @MainActor in self.authorized = false }
            }
        }
    }

    /// Post an immediate local notification. No-op while the app is active
    /// (foreground) unless `force` is true.
    func notify(title: String, body: String, id: String = UUID().uuidString, force: Bool = false) {
        guard force || UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Hold a short background-execution window so the in-app event stream can
    /// process a run that finishes just after the app is backgrounded (iOS
    /// otherwise suspends networking almost immediately). This buys ~30s — long
    /// runs still won't deliver until the app is reopened, since opencode has no
    /// server-side push.
    func beginBackgroundGrace() {
        endBackgroundGrace()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "korbo.run") { [weak self] in
            self?.endBackgroundGrace()
        }
    }

    func endBackgroundGrace() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }
}
