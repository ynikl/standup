import Foundation
import StandUpCore

#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
protocol StandUpNotificationScheduling {
    func requestAuthorization() async throws -> Bool
    func replaceSedentaryReminders(with plan: ReminderPlan) async throws
    func cancelSedentaryReminders() async
}

struct LocalStandUpNotificationScheduler: StandUpNotificationScheduling {
    private let notificationPrefix = "sedentary-reminder"

    #if canImport(UserNotifications)
    func requests(for plan: ReminderPlan, now: Date) -> [UNNotificationRequest] {
        plan.reminders.map { reminder in
            let content = UNMutableNotificationContent()
            content.title = reminder.reason == .repeatReminder ? "Still sitting" : "Time to stand"
            content.body = "Stand or walk for 2 minutes to reset your sedentary timer."
            content.sound = .default
            content.categoryIdentifier = "SEDENTARY_REMINDER"

            return UNNotificationRequest(
                identifier: "\(notificationPrefix)-\(reminder.id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, reminder.deliveryDate.timeIntervalSince(now)),
                    repeats: false
                )
            )
        }
    }
    #endif

    func requestAuthorization() async throws -> Bool {
        #if canImport(UserNotifications)
        return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        #else
        return false
        #endif
    }

    func replaceSedentaryReminders(with plan: ReminderPlan) async throws {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        for request in requests(for: plan, now: Date()) {
            try await center.add(request)
        }
        #endif
    }

    func cancelSedentaryReminders() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        #endif
    }
}
