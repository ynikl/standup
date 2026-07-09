import Foundation

public struct IgnoreEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var duration: IgnoreDuration
    public var startedAt: Date
    public var until: Date

    public init(id: UUID = UUID(), duration: IgnoreDuration, startedAt: Date, until: Date) {
        self.id = id
        self.duration = duration
        self.startedAt = startedAt
        self.until = until
    }
}

public struct SedentaryRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sedentaryStartedAt: Date
    public var thresholdReachedAt: Date
    public var endedAt: Date
    public var endReason: SedentaryEndReason
    public var ignoreEvents: [IgnoreEvent]
    public var correction: RecordCorrection?

    public init(
        id: UUID = UUID(),
        sedentaryStartedAt: Date,
        thresholdReachedAt: Date,
        endedAt: Date,
        endReason: SedentaryEndReason,
        ignoreEvents: [IgnoreEvent],
        correction: RecordCorrection? = nil
    ) {
        self.id = id
        self.sedentaryStartedAt = sedentaryStartedAt
        self.thresholdReachedAt = thresholdReachedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.ignoreEvents = ignoreEvents
        self.correction = correction
    }

    public var overageMinutes: Int {
        max(0, Int(endedAt.timeIntervalSince(thresholdReachedAt) / 60))
    }

    public var continuousSedentaryMinutes: Int {
        max(0, Int(endedAt.timeIntervalSince(sedentaryStartedAt) / 60))
    }

    public var isExcludedFromStats: Bool {
        correction?.isExcluded ?? false
    }
}

public enum SedentaryEndReason: String, Codable, Equatable, Sendable {
    case stoodUp
    case monitoringInterrupted
    case outsideActiveWindow
}

public enum RecordCorrection: Codable, Equatable, Sendable {
    case excluded(reason: CorrectionReason)

    public var isExcluded: Bool {
        switch self {
        case .excluded:
            return true
        }
    }
}

public enum CorrectionReason: String, Codable, Equatable, CaseIterable, Sendable {
    case watchingMovie
    case meeting
    case alreadyStood
    case other

    public var displayTitle: String {
        switch self {
        case .watchingMovie:
            return "Watching movie"
        case .meeting:
            return "Meeting"
        case .alreadyStood:
            return "Already stood"
        case .other:
            return "Other"
        }
    }
}
