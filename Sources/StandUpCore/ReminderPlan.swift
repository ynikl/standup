import Foundation

public struct PlannedReminder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var deliveryDate: Date
    public var reason: NotificationReason

    public init(id: String, deliveryDate: Date, reason: NotificationReason) {
        self.id = id
        self.deliveryDate = deliveryDate
        self.reason = reason
    }
}

public struct ReminderPlan: Codable, Equatable, Sendable {
    public static let empty = ReminderPlan(reminders: [])

    public var reminders: [PlannedReminder]

    public init(reminders: [PlannedReminder]) {
        self.reminders = reminders
    }
}
