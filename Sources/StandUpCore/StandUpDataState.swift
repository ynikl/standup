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

        var recordsByID: [SedentaryRecord.ID: SedentaryRecord] = [:]
        func mergeRecord(_ record: SedentaryRecord) {
            guard let existing = recordsByID[record.id] else {
                recordsByID[record.id] = record
                return
            }

            if record.modifiedAt > existing.modifiedAt {
                recordsByID[record.id] = record
            }
        }

        records.forEach(mergeRecord)
        incoming.records.forEach(mergeRecord)

        return StandUpDataState(
            settings: mergedSettings,
            settingsUpdatedAt: mergedSettingsUpdatedAt,
            records: recordsByID.values.sorted { $0.thresholdReachedAt > $1.thresholdReachedAt }
        )
    }
}

public struct StandUpLocalState: Codable, Equatable, Sendable {
    public var synchronized: StandUpDataState
    public var session: SedentarySessionState

    public init(synchronized: StandUpDataState, session: SedentarySessionState = .empty) {
        self.synchronized = synchronized
        self.session = session
    }

    private enum CodingKeys: String, CodingKey {
        case synchronized
        case session
        case settings
        case records
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let synchronized = try container.decodeIfPresent(StandUpDataState.self, forKey: .synchronized) {
            self.synchronized = synchronized
        } else {
            self.synchronized = StandUpDataState(
                settings: try container.decode(StandUpSettings.self, forKey: .settings),
                settingsUpdatedAt: Date(timeIntervalSince1970: 0),
                records: try container.decode([SedentaryRecord].self, forKey: .records)
            )
        }
        session = try container.decodeIfPresent(SedentarySessionState.self, forKey: .session) ?? .empty
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(synchronized, forKey: .synchronized)
        try container.encode(session, forKey: .session)
    }
}
