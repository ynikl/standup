import Foundation
import StandUpCore

enum StandUpFormatting {
    static func minutes(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        if value < 60 {
            return "\(value) 分钟"
        }

        let hours = value / 60
        let mins = value % 60
        if mins == 0 {
            return "\(hours) 小时"
        }
        return "\(hours) 小时 \(mins) 分"
    }

    /// 紧凑时长（用于窄卡片、统计磁贴）：45分 / 1时 / 1时5分
    static func compactMinutes(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        if value < 60 {
            return "\(value)分"
        }

        let hours = value / 60
        let mins = value % 60
        return mins == 0 ? "\(hours)时" : "\(hours)时\(mins)分"
    }

    static func timeRange(_ record: SedentaryRecord) -> String {
        "\(time(record.thresholdReachedAt)) - \(time(record.endedAt))"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
