import Foundation

public enum SedentaryAnalytics {
    public static func emptyDailySummaries(endingOn endDate: Date, days: Int, calendar: Calendar = .current) -> [DailySedentarySummary] {
        guard days > 0 else {
            return []
        }

        let endDay = calendar.startOfDay(for: endDate)
        let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }
            return DailySedentarySummary(day: day, overdueCount: 0, totalOverageMinutes: 0, longestContinuousSedentaryMinutes: 0)
        }
    }

    public static func dailySummaries(
        records: [SedentaryRecord],
        endingOn endDate: Date,
        days: Int,
        calendar: Calendar = .current
    ) -> [DailySedentarySummary] {
        var summaries = emptyDailySummaries(endingOn: endDate, days: days, calendar: calendar)
        guard !summaries.isEmpty else {
            return summaries
        }

        let dayIndices = Dictionary(uniqueKeysWithValues: summaries.enumerated().map { index, summary in
            (calendar.startOfDay(for: summary.day), index)
        })

        for record in records where !record.isExcludedFromStats {
            let day = calendar.startOfDay(for: record.thresholdReachedAt)
            guard let index = dayIndices[day] else {
                continue
            }

            summaries[index].overdueCount += 1
            summaries[index].totalOverageMinutes += record.overageMinutes
            summaries[index].longestContinuousSedentaryMinutes = max(
                summaries[index].longestContinuousSedentaryMinutes,
                record.continuousSedentaryMinutes
            )
        }

        return summaries
    }
}

public struct DailySedentarySummary: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { day }

    public var day: Date
    public var overdueCount: Int
    public var totalOverageMinutes: Int
    public var longestContinuousSedentaryMinutes: Int

    public init(day: Date, overdueCount: Int, totalOverageMinutes: Int, longestContinuousSedentaryMinutes: Int) {
        self.day = day
        self.overdueCount = overdueCount
        self.totalOverageMinutes = totalOverageMinutes
        self.longestContinuousSedentaryMinutes = longestContinuousSedentaryMinutes
    }
}
