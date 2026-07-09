import Foundation
import StandUpCore

#if canImport(UserNotifications)
import UserNotifications
#endif

protocol StandUpNotificationScheduling {
    func requestAuthorization() async throws -> Bool
    func scheduleSedentaryReminder(reason: NotificationReason?, seatedMinutes: Int?) async
    func scheduleSedentaryReminder(at date: Date, reason: NotificationReason?) async
    func cancelSedentaryReminders() async
}

struct LocalStandUpNotificationScheduler: StandUpNotificationScheduling {
    private let notificationPrefix = "sedentary-reminder"

    func requestAuthorization() async throws -> Bool {
        #if canImport(UserNotifications)
        return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        #else
        return false
        #endif
    }

    func scheduleSedentaryReminder(reason: NotificationReason?, seatedMinutes: Int?) async {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = reason == .repeatReminder ? "Still sitting" : "Time to stand"
        if let seatedMinutes {
            content.body = "You've been sitting for about \(seatedMinutes) minutes. Stand or walk for 2 minutes to reset."
        } else {
            content.body = "Stand or walk for 2 minutes to reset your sedentary timer."
        }
        content.sound = .default
        content.categoryIdentifier = "SEDENTARY_REMINDER"

        let request = UNNotificationRequest(
            identifier: "\(notificationPrefix)-now-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
        #endif
    }

    func scheduleSedentaryReminder(at date: Date, reason: NotificationReason?) async {
        #if canImport(UserNotifications)
        await cancelSedentaryReminders()

        let seconds = max(1, date.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = reason == .repeatReminder ? "Still sitting" : "Time to stand"
        content.body = "Stand or walk for 2 minutes to reset your sedentary timer."
        content.sound = .default
        content.categoryIdentifier = "SEDENTARY_REMINDER"

        let request = UNNotificationRequest(
            identifier: "\(notificationPrefix)-scheduled",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
        #endif
    }

    func cancelSedentaryReminders() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["\(notificationPrefix)-scheduled"])
        #endif
    }
}
