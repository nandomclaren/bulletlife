// Close the day as a notification (CLAUDE.md 5 and 14): a quiet daily reminder at the time set in Settings.
// It only reminds: tapping it opens tomorrow's page with what is still open today beside it, as the in-app
// banner does; nothing is written.
import SwiftUI
import UIKit
import UserNotifications

enum Reminders {
    static let closeDayId = "closeDay"
    /// Posted when the reminder is tapped; the window opens tomorrow and the panel.
    static let openCloseDay = Notification.Name("BulletLife.openCloseDay")

    /// Asks once, when the user turns the reminder on. False if notifications are not allowed.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Schedules (or removes) the daily reminder from the settings as they are now.
    static func update() {
        let d = UserDefaults.standard
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [closeDayId])
        let on = (d.object(forKey: "closeDay") as? Bool ?? true) && d.bool(forKey: "closeDayNotify")
            && (d.object(forKey: "logDaily") as? Bool ?? true)
        guard on else { return }
        let parts = (d.string(forKey: "closeDayAt") ?? "20:00").split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        let content = UNMutableNotificationContent()
        content.title = S.closeDay
        content.body = S.closeDayHint
        content.sound = .default
        let when = DateComponents(hour: parts[0], minute: parts[1])
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        center.add(UNNotificationRequest(identifier: closeDayId, content: content, trigger: trigger))
    }
}

/// Receives the reminder's tap (and keeps it quiet while the app is open: the banner is there).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.update()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == Reminders.closeDayId {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Reminders.openCloseDay, object: nil) }
        }
        completionHandler()
    }
}
