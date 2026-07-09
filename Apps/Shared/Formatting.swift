import Foundation
import StandUpCore

enum StandUpFormatting {
    static func minutes(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        if value < 60 {
            return "\(value)m"
        }

        return "\(value / 60)h \(value % 60)m"
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
