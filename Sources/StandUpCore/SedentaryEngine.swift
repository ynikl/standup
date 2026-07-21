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
    public var latestActivity: ActivitySignal?
    public var lastActivityAt: Date?

    public init(
        seatedSince: Date? = nil,
        thresholdReachedAt: Date? = nil,
        activeCandidateSince: Date? = nil,
        lastReminderAt: Date? = nil,
        ignoreUntil: Date? = nil,
        ignoreEvents: [IgnoreEvent] = [],
        pauseReason: PauseReason? = nil,
        latestActivity: ActivitySignal? = nil,
        lastActivityAt: Date? = nil
    ) {
        self.seatedSince = seatedSince
        self.thresholdReachedAt = thresholdReachedAt
        self.activeCandidateSince = activeCandidateSince
        self.lastReminderAt = lastReminderAt
        self.ignoreUntil = ignoreUntil
        self.ignoreEvents = ignoreEvents
        self.pauseReason = pauseReason
        self.latestActivity = latestActivity
        self.lastActivityAt = lastActivityAt
    }

    private enum CodingKeys: String, CodingKey {
        case seatedSince
        case thresholdReachedAt
        case activeCandidateSince
        case lastReminderAt
        case ignoreUntil
        case ignoreEvents
        case pauseReason
        case latestActivity
        case lastActivityAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seatedSince = try container.decodeIfPresent(Date.self, forKey: .seatedSince)
        thresholdReachedAt = try container.decodeIfPresent(Date.self, forKey: .thresholdReachedAt)
        activeCandidateSince = try container.decodeIfPresent(Date.self, forKey: .activeCandidateSince)
        lastReminderAt = try container.decodeIfPresent(Date.self, forKey: .lastReminderAt)
        ignoreUntil = try container.decodeIfPresent(Date.self, forKey: .ignoreUntil)
        ignoreEvents = try container.decodeIfPresent([IgnoreEvent].self, forKey: .ignoreEvents) ?? []
        pauseReason = try container.decodeIfPresent(PauseReason.self, forKey: .pauseReason)
        latestActivity = try container.decodeIfPresent(ActivitySignal.self, forKey: .latestActivity)
            ?? (activeCandidateSince != nil ? .active : seatedSince != nil ? .sedentary : nil)
        lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt)
            ?? activeCandidateSince
            ?? seatedSince
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
    private var latestActivity: ActivitySignal?
    private var lastActivityAt: Date?

    public init(
        settings: StandUpSettings,
        calendar: Calendar = .current,
        sessionState: SedentarySessionState = .empty,
        restoredAt: Date = Date()
    ) {
        self.settings = settings
        self.calendar = calendar
        let restoredState = Self.isValid(
            sessionState,
            settings: settings,
            calendar: calendar,
            restoredAt: restoredAt
        ) ? sessionState : .empty
        self.seatedSince = restoredState.seatedSince
        self.thresholdReachedAt = restoredState.thresholdReachedAt
        self.activeCandidateSince = restoredState.activeCandidateSince
        self.lastReminderAt = restoredState.lastReminderAt
        self.ignoreUntil = restoredState.ignoreUntil
        self.ignoreEvents = restoredState.ignoreEvents
        self.pauseReason = restoredState.pauseReason
        self.latestActivity = restoredState.latestActivity
        self.lastActivityAt = restoredState.lastActivityAt
    }

    public var sessionState: SedentarySessionState {
        SedentarySessionState(
            seatedSince: seatedSince,
            thresholdReachedAt: thresholdReachedAt,
            activeCandidateSince: activeCandidateSince,
            lastReminderAt: lastReminderAt,
            ignoreUntil: ignoreUntil,
            ignoreEvents: ignoreEvents,
            pauseReason: pauseReason,
            latestActivity: latestActivity,
            lastActivityAt: lastActivityAt
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
            if let lastActivityAt, now <= lastActivityAt {
                return .empty
            }
            lastActivityAt = now

            switch activity {
            case .sedentary:
                pauseReason = nil
                // A stationary sample marks the end of the current active
                // period. Core Motion usually reports a walk as a single active
                // sample followed directly by this stationary sample, so the
                // active duration must be credited here at the transition —
                // otherwise a real walk is never counted and the previous
                // sedentary timer keeps running. Evaluate the clear before
                // overwriting `latestActivity` so the elapsed active minutes
                // (from `activeCandidateSince` to `now`) are measured against
                // the accurate transition timestamps.
                if let ended = evaluateActiveClear(at: now) {
                    latestActivity = .sedentary
                    seatedSince = now
                    return EngineOutput(endedRecords: ended)
                }

                latestActivity = .sedentary
                activeCandidateSince = nil
                if seatedSince == nil {
                    seatedSince = now
                }
                return evaluateReminder(at: now)

            case .active:
                latestActivity = .active
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
                latestActivity = .unavailable
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

    public func reminderPlan(at now: Date, limit: Int = 60) -> ReminderPlan {
        guard limit > 0, pauseReason == nil, activeCandidateSince == nil, let seatedSince else {
            return .empty
        }

        let thresholdDate = seatedSince.addingTimeInterval(TimeInterval(settings.sedentaryThresholdMinutes * 60))
        let firstReason: NotificationReason
        let cadenceDate: Date
        if thresholdReachedAt == nil {
            firstReason = .thresholdReached
            cadenceDate = thresholdDate
        } else {
            firstReason = .repeatReminder
            cadenceDate = (lastReminderAt ?? thresholdDate).addingTimeInterval(
                TimeInterval(settings.repeatReminderMinutes * 60)
            )
        }

        let firstDeliveryDate = max(now, cadenceDate, ignoreUntil ?? cadenceDate)
        guard let activeWindowEnd = settings.activeWindow.end(containing: now, calendar: calendar),
              firstDeliveryDate < activeWindowEnd else {
            return .empty
        }

        var reminders: [PlannedReminder] = []
        var deliveryDate = firstDeliveryDate
        while deliveryDate < activeWindowEnd, reminders.count < limit {
            let reason = reminders.isEmpty ? firstReason : NotificationReason.repeatReminder
            reminders.append(
                PlannedReminder(
                    id: "\(reason.rawValue)-\(Int(deliveryDate.timeIntervalSince1970))",
                    deliveryDate: deliveryDate,
                    reason: reason
                )
            )
            deliveryDate = deliveryDate.addingTimeInterval(TimeInterval(settings.repeatReminderMinutes * 60))
        }

        return ReminderPlan(reminders: reminders)
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
        guard latestActivity == .active, let activeCandidateSince else {
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
        latestActivity = nil
    }

    private static func isValid(
        _ state: SedentarySessionState,
        settings: StandUpSettings,
        calendar: Calendar,
        restoredAt: Date
    ) -> Bool {
        if let seatedSince = state.seatedSince {
            guard seatedSince <= restoredAt,
                  settings.activeWindow.contains(seatedSince, calendar: calendar),
                  settings.activeWindow.contains(restoredAt, calendar: calendar),
                  let windowEnd = settings.activeWindow.end(containing: seatedSince, calendar: calendar),
                  restoredAt < windowEnd else {
                return false
            }
        } else if state.thresholdReachedAt != nil
            || state.activeCandidateSince != nil
            || state.lastReminderAt != nil
            || !state.ignoreEvents.isEmpty {
            return false
        }

        if let thresholdReachedAt = state.thresholdReachedAt {
            guard let seatedSince = state.seatedSince,
                  thresholdReachedAt >= seatedSince,
                  thresholdReachedAt <= restoredAt else {
                return false
            }
        }

        if let lastReminderAt = state.lastReminderAt {
            guard let thresholdReachedAt = state.thresholdReachedAt,
                  lastReminderAt >= thresholdReachedAt,
                  lastReminderAt <= restoredAt else {
                return false
            }
        }

        if let activeCandidateSince = state.activeCandidateSince {
            guard let seatedSince = state.seatedSince,
                  state.latestActivity == .active,
                  activeCandidateSince >= seatedSince,
                  activeCandidateSince <= restoredAt else {
                return false
            }
        } else if state.latestActivity == .active {
            return false
        }

        if let lastActivityAt = state.lastActivityAt, lastActivityAt > restoredAt {
            return false
        }

        if state.pauseReason != nil, state.seatedSince != nil {
            return false
        }

        for event in state.ignoreEvents {
            guard let thresholdReachedAt = state.thresholdReachedAt,
                  event.startedAt >= thresholdReachedAt,
                  event.startedAt <= restoredAt,
                  event.until >= event.startedAt else {
                return false
            }
        }

        return true
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
