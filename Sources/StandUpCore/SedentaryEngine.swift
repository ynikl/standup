import Foundation

public struct SedentarySessionState: Codable, Equatable, Sendable {
    public static let empty = SedentarySessionState()

    public var seatedSince: Date?
    public var thresholdReachedAt: Date?
    public var activeCandidateSince: Date?
    public var lastReminderAt: Date?
    public var ignoreUntil: Date?
    public var ignoreEvents: [IgnoreEvent]
    public var pauseReason: PauseReason?

    public init(
        seatedSince: Date? = nil,
        thresholdReachedAt: Date? = nil,
        activeCandidateSince: Date? = nil,
        lastReminderAt: Date? = nil,
        ignoreUntil: Date? = nil,
        ignoreEvents: [IgnoreEvent] = [],
        pauseReason: PauseReason? = nil
    ) {
        self.seatedSince = seatedSince
        self.thresholdReachedAt = thresholdReachedAt
        self.activeCandidateSince = activeCandidateSince
        self.lastReminderAt = lastReminderAt
        self.ignoreUntil = ignoreUntil
        self.ignoreEvents = ignoreEvents
        self.pauseReason = pauseReason
    }
}

public struct SedentaryEngine: Equatable, Sendable {
    public private(set) var settings: StandUpSettings

    private var calendar: Calendar
    private var seatedSince: Date?
    private var thresholdReachedAt: Date?
    private var activeCandidateSince: Date?
    private var lastReminderAt: Date?
    private var ignoreUntil: Date?
    private var ignoreEvents: [IgnoreEvent]
    private var pauseReason: PauseReason?

    public init(
        settings: StandUpSettings,
        calendar: Calendar = .current,
        sessionState: SedentarySessionState = .empty
    ) {
        self.settings = settings
        self.calendar = calendar
        self.seatedSince = sessionState.seatedSince
        self.thresholdReachedAt = sessionState.thresholdReachedAt
        self.activeCandidateSince = sessionState.activeCandidateSince
        self.lastReminderAt = sessionState.lastReminderAt
        self.ignoreUntil = sessionState.ignoreUntil
        self.ignoreEvents = sessionState.ignoreEvents
        self.pauseReason = sessionState.pauseReason
    }

    public var sessionState: SedentarySessionState {
        SedentarySessionState(
            seatedSince: seatedSince,
            thresholdReachedAt: thresholdReachedAt,
            activeCandidateSince: activeCandidateSince,
            lastReminderAt: lastReminderAt,
            ignoreUntil: ignoreUntil,
            ignoreEvents: ignoreEvents,
            pauseReason: pauseReason
        )
    }

    public mutating func update(settings: StandUpSettings) {
        self.settings = settings
    }

    public mutating func ingest(_ event: StandUpEvent, at now: Date) -> EngineOutput {
        guard settings.activeWindow.contains(now, calendar: calendar) else {
            return pause(.outsideActiveWindow, at: now)
        }

        switch event {
        case .tick:
            if let ended = evaluateActiveClear(at: now) {
                return EngineOutput(endedRecords: ended)
            }
            return evaluateReminder(at: now)

        case .activity(let activity):
            switch activity {
            case .sedentary:
                pauseReason = nil
                activeCandidateSince = nil
                if seatedSince == nil {
                    seatedSince = now
                }
                return evaluateReminder(at: now)

            case .active:
                pauseReason = nil
                if activeCandidateSince == nil {
                    activeCandidateSince = now
                    return .empty
                }

                if let ended = evaluateActiveClear(at: now) {
                    return EngineOutput(endedRecords: ended)
                }

                return .empty

            case .unavailable:
                return pause(.sensorUnavailable, at: now)
            }

        case .ignore(let duration):
            let until = duration.endDate(startedAt: now, settings: settings, calendar: calendar)
            ignoreUntil = until
            if thresholdReachedAt != nil {
                ignoreEvents.append(IgnoreEvent(duration: duration, startedAt: now, until: until))
            }
            return .empty
        }
    }

    public func snapshot(at now: Date) -> SedentarySnapshot {
        if !settings.activeWindow.contains(now, calendar: calendar) {
            return SedentarySnapshot(phase: .paused(.outsideActiveWindow), seatedMinutes: nil, ignoreUntil: ignoreUntil)
        }

        if let pauseReason {
            return SedentarySnapshot(phase: .paused(pauseReason), seatedMinutes: nil, ignoreUntil: ignoreUntil)
        }

        let seatedMinutes = seatedSince.map { max(0, Int(now.timeIntervalSince($0) / 60)) }

        if let ignoreUntil, ignoreUntil > now {
            return SedentarySnapshot(phase: .ignored(until: ignoreUntil), seatedMinutes: seatedMinutes, ignoreUntil: ignoreUntil)
        }

        if let seatedSince, now.timeIntervalSince(seatedSince) >= TimeInterval(settings.sedentaryThresholdMinutes * 60) {
            return SedentarySnapshot(phase: .overdue, seatedMinutes: seatedMinutes, ignoreUntil: nil)
        }

        return SedentarySnapshot(phase: .monitoring, seatedMinutes: seatedMinutes, ignoreUntil: nil)
    }

    private mutating func evaluateReminder(at now: Date) -> EngineOutput {
        guard pauseReason == nil, let seatedSince else {
            return .empty
        }

        if let ignoreUntil, ignoreUntil > now {
            return .empty
        }

        let thresholdDate = seatedSince.addingTimeInterval(TimeInterval(settings.sedentaryThresholdMinutes * 60))
        guard now >= thresholdDate else {
            return .empty
        }

        if thresholdReachedAt == nil {
            thresholdReachedAt = thresholdDate
            lastReminderAt = now
            return EngineOutput(shouldNotify: true, notificationReason: .thresholdReached)
        }

        if let lastReminderAt {
            let elapsed = now.timeIntervalSince(lastReminderAt)
            guard elapsed >= TimeInterval(settings.repeatReminderMinutes * 60) else {
                return .empty
            }
        }

        lastReminderAt = now
        return EngineOutput(shouldNotify: true, notificationReason: .repeatReminder)
    }

    private mutating func evaluateActiveClear(at now: Date) -> [SedentaryRecord]? {
        guard let activeCandidateSince else {
            return nil
        }

        let activeMinutes = Int(now.timeIntervalSince(activeCandidateSince) / 60)
        guard activeMinutes >= settings.activeClearMinutes else {
            return nil
        }

        return finishSession(at: now, reason: .stoodUp)
    }

    private mutating func pause(_ reason: PauseReason, at now: Date) -> EngineOutput {
        let ended: [SedentaryRecord]
        if thresholdReachedAt != nil {
            let endReason: SedentaryEndReason = reason == .outsideActiveWindow ? .outsideActiveWindow : .monitoringInterrupted
            ended = finishSession(at: now, reason: endReason)
        } else {
            clearSession()
            ended = []
        }

        pauseReason = reason
        return EngineOutput(endedRecords: ended)
    }

    private mutating func finishSession(at now: Date, reason: SedentaryEndReason) -> [SedentaryRecord] {
        defer {
            clearSession()
        }

        guard let sedentaryStartedAt = seatedSince, let thresholdReachedAt else {
            return []
        }

        return [
            SedentaryRecord(
                sedentaryStartedAt: sedentaryStartedAt,
                thresholdReachedAt: thresholdReachedAt,
                endedAt: now,
                endReason: reason,
                ignoreEvents: ignoreEvents
            )
        ]
    }

    private mutating func clearSession() {
        seatedSince = nil
        thresholdReachedAt = nil
        activeCandidateSince = nil
        lastReminderAt = nil
        ignoreUntil = nil
        ignoreEvents = []
    }
}

public enum StandUpEvent: Equatable, Sendable {
    case tick
    case activity(ActivitySignal)
    case ignore(IgnoreDuration)
}

public enum ActivitySignal: String, Codable, Equatable, Sendable {
    case sedentary
    case active
    case unavailable
}

public struct SedentarySnapshot: Equatable, Sendable {
    public var phase: MonitoringPhase
    public var seatedMinutes: Int?
    public var ignoreUntil: Date?

    public init(phase: MonitoringPhase, seatedMinutes: Int?, ignoreUntil: Date?) {
        self.phase = phase
        self.seatedMinutes = seatedMinutes
        self.ignoreUntil = ignoreUntil
    }
}

public enum MonitoringPhase: Equatable, Sendable {
    case monitoring
    case overdue
    case ignored(until: Date)
    case paused(PauseReason)
}

public enum PauseReason: String, Codable, Equatable, Sendable {
    case sensorUnavailable
    case outsideActiveWindow
}

public struct EngineOutput: Equatable, Sendable {
    public static let empty = EngineOutput()

    public var shouldNotify: Bool
    public var notificationReason: NotificationReason?
    public var endedRecords: [SedentaryRecord]

    public init(
        shouldNotify: Bool = false,
        notificationReason: NotificationReason? = nil,
        endedRecords: [SedentaryRecord] = []
    ) {
        self.shouldNotify = shouldNotify
        self.notificationReason = notificationReason
        self.endedRecords = endedRecords
    }
}

public enum NotificationReason: String, Codable, Equatable, Sendable {
    case thresholdReached
    case repeatReminder
}
