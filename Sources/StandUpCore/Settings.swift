import Foundation

public struct StandUpSettings: Codable, Equatable, Sendable {
    public static let `default` = StandUpSettings()

    public var sedentaryThresholdMinutes: Int
    public var activeClearMinutes: Int
    public var repeatReminderMinutes: Int
    public var activeWindow: ActiveWindow

    public init(
        sedentaryThresholdMinutes: Int = 45,
        activeClearMinutes: Int = 2,
        repeatReminderMinutes: Int = 10,
        activeWindow: ActiveWindow = .default
    ) {
        self.sedentaryThresholdMinutes = Self.normalizeThreshold(sedentaryThresholdMinutes)
        self.activeClearMinutes = max(1, activeClearMinutes)
        self.repeatReminderMinutes = max(1, repeatReminderMinutes)
        self.activeWindow = activeWindow
    }

    private static func normalizeThreshold(_ minutes: Int) -> Int {
        let clamped = min(120, max(15, minutes))
        return Int((Double(clamped) / 5.0).rounded()) * 5
    }
}

public struct ActiveWindow: Codable, Equatable, Sendable {
    public static let `default` = ActiveWindow(startMinuteOfDay: 9 * 60, endMinuteOfDay: 22 * 60)

    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int

    public init(startMinuteOfDay: Int, endMinuteOfDay: Int) {
        self.startMinuteOfDay = min(24 * 60, max(0, startMinuteOfDay))
        self.endMinuteOfDay = min(24 * 60, max(0, endMinuteOfDay))
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if startMinuteOfDay < endMinuteOfDay {
            return minuteOfDay >= startMinuteOfDay && minuteOfDay < endMinuteOfDay
        }

        if startMinuteOfDay > endMinuteOfDay {
            return minuteOfDay >= startMinuteOfDay || minuteOfDay < endMinuteOfDay
        }

        return true
    }

    public func nextStart(after date: Date, calendar: Calendar) -> Date {
        let todayStart = start(on: date, calendar: calendar)
        if todayStart > date {
            return todayStart
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(24 * 60 * 60)
        return start(on: tomorrow, calendar: calendar)
    }

    public func end(containing date: Date, calendar: Calendar) -> Date? {
        guard contains(date, calendar: calendar) else {
            return nil
        }

        let todayEnd = wallClockDate(on: date, minuteOfDay: endMinuteOfDay, calendar: calendar)
        if startMinuteOfDay < endMinuteOfDay || todayEnd > date {
            return todayEnd
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(24 * 60 * 60)
        return wallClockDate(on: tomorrow, minuteOfDay: endMinuteOfDay, calendar: calendar)
    }

    public func start(on date: Date, calendar: Calendar) -> Date {
        wallClockDate(on: date, minuteOfDay: startMinuteOfDay, calendar: calendar)
    }

    public func start(containing date: Date, calendar: Calendar) -> Date? {
        guard contains(date, calendar: calendar) else {
            return nil
        }

        let todayStart = start(on: date, calendar: calendar)
        if todayStart <= date {
            return todayStart
        }

        let previousDay = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: date)
        ) ?? date.addingTimeInterval(-24 * 60 * 60)
        return start(on: previousDay, calendar: calendar)
    }

    private func wallClockDate(on date: Date, minuteOfDay: Int, calendar: Calendar) -> Date {
        let dayOffset = minuteOfDay / (24 * 60)
        let normalizedMinute = minuteOfDay % (24 * 60)
        let baseDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: date)
        ) ?? calendar.startOfDay(for: date)

        return calendar.date(
            bySettingHour: normalizedMinute / 60,
            minute: normalizedMinute % 60,
            second: 0,
            of: baseDay
        ) ?? baseDay
    }
}

public enum IgnoreDuration: String, CaseIterable, Codable, Equatable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case untilTomorrow

    public var minutes: Int? {
        switch self {
        case .fifteenMinutes:
            return 15
        case .thirtyMinutes:
            return 30
        case .oneHour:
            return 60
        case .twoHours:
            return 120
        case .untilTomorrow:
            return nil
        }
    }

    public var displayTitle: String {
        switch self {
        case .fifteenMinutes:
            return "15 分钟"
        case .thirtyMinutes:
            return "30 分钟"
        case .oneHour:
            return "1 小时"
        case .twoHours:
            return "2 小时"
        case .untilTomorrow:
            return "直到明天"
        }
    }

    public func endDate(startedAt date: Date, settings: StandUpSettings, calendar: Calendar) -> Date {
        if let minutes {
            return date.addingTimeInterval(TimeInterval(minutes * 60))
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(24 * 60 * 60)
        return settings.activeWindow.start(on: tomorrow, calendar: calendar)
    }
}
