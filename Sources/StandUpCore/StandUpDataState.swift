import Foundation

public struct StandUpDataState: Codable, Equatable, Sendable {
    public var settings: StandUpSettings
    public var settingsUpdatedAt: Date
    public var records: [SedentaryRecord]

    public init(settings: StandUpSettings, settingsUpdatedAt: Date, records: [SedentaryRecord]) {
        self.settings = settings
        self.settingsUpdatedAt = settingsUpdatedAt
        self.records = records
    }

    public func merging(_ incoming: StandUpDataState) -> StandUpDataState {
        let mergedSettings: StandUpSettings
        let mergedSettingsUpdatedAt: Date
        if incoming.settingsUpdatedAt > settingsUpdatedAt {
            mergedSettings = incoming.settings
            mergedSettingsUpdatedAt = incoming.settingsUpdatedAt
        } else {
            mergedSettings = settings
            mergedSettingsUpdatedAt = settingsUpdatedAt
        }

        var recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for record in incoming.records {
            guard let existing = recordsByID[record.id] else {
                recordsByID[record.id] = record
                continue
            }

            if record.modifiedAt > existing.modifiedAt {
                recordsByID[record.id] = record
            }
        }

        return StandUpDataState(
            settings: mergedSettings,
            settingsUpdatedAt: mergedSettingsUpdatedAt,
            records: recordsByID.values.sorted { $0.thresholdReachedAt > $1.thresholdReachedAt }
        )
    }
}
