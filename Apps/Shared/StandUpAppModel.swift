import Foundation
import StandUpCore

#if canImport(Combine)
import Combine
#endif

@MainActor
final class StandUpAppModel: ObservableObject {
    @Published var settings: StandUpSettings
    @Published var records: [SedentaryRecord]
    @Published var snapshot: SedentarySnapshot
    @Published var permissionState: PermissionState
    @Published var lastNotificationReason: NotificationReason?

    private var engine: SedentaryEngine
    private let storage: StandUpStorage
    private let notifier: StandUpNotificationScheduling
    private let sync: StandUpSyncing
    private var scheduledReminderAt: Date?
    private var settingsUpdatedAt: Date

    init(
        storage: StandUpStorage? = nil,
        notifier: StandUpNotificationScheduling? = nil,
        sync: StandUpSyncing? = nil,
        now: Date = Date()
    ) {
        let storage = storage ?? LocalJSONStandUpStorage()
        let notifier = notifier ?? LocalStandUpNotificationScheduler()
        let sync = sync ?? WatchConnectivityStandUpBridge()
        self.storage = storage
        self.notifier = notifier
        self.sync = sync

        let persisted = (try? storage.load()) ?? StandUpLocalState(
            synchronized: StandUpDataState(
                settings: .default,
                settingsUpdatedAt: Date(timeIntervalSince1970: 0),
                records: []
            )
        )
        self.settings = persisted.synchronized.settings
        self.settingsUpdatedAt = persisted.synchronized.settingsUpdatedAt
        self.records = persisted.synchronized.records.sorted { $0.thresholdReachedAt > $1.thresholdReachedAt }
        self.permissionState = .unknown
        self.engine = SedentaryEngine(settings: persisted.synchronized.settings, sessionState: persisted.session)
        self.snapshot = engine.snapshot(at: now)

        self.sync.onReceive = { [weak self] state in
            self?.merge(state)
        }
        self.sync.activate()
    }

    func refresh(now: Date = Date()) {
        apply(engine.ingest(.tick, at: now), at: now)
    }

    func ingest(activity: ActivitySignal, now: Date = Date()) {
        permissionState.motionAllowed = activity == .unavailable ? false : true
        apply(engine.ingest(.activity(activity), at: now), at: now)

        if activity == .active || activity == .unavailable {
            cancelScheduledReminder()
        } else {
            scheduleNextReminderIfNeeded(now: now)
        }
    }

    func ignore(_ duration: IgnoreDuration, now: Date = Date()) {
        apply(engine.ingest(.ignore(duration), at: now), at: now)
        scheduleNextReminderIfNeeded(now: now)
    }

    func updateThreshold(minutes: Int, now: Date = Date()) {
        settings = StandUpSettings(
            sedentaryThresholdMinutes: minutes,
            activeClearMinutes: settings.activeClearMinutes,
            repeatReminderMinutes: settings.repeatReminderMinutes,
            activeWindow: settings.activeWindow
        )
        settingsUpdatedAt = now
        engine.update(settings: settings)
        persist(synchronize: true)
    }

    func updateActiveWindow(startHour: Int, endHour: Int, now: Date = Date()) {
        settings = StandUpSettings(
            sedentaryThresholdMinutes: settings.sedentaryThresholdMinutes,
            activeClearMinutes: settings.activeClearMinutes,
            repeatReminderMinutes: settings.repeatReminderMinutes,
            activeWindow: ActiveWindow(startMinuteOfDay: startHour * 60, endMinuteOfDay: endHour * 60)
        )
        settingsUpdatedAt = now
        engine.update(settings: settings)
        persist(synchronize: true)
    }

    func correct(recordID: SedentaryRecord.ID, reason: CorrectionReason, now: Date = Date()) {
        records = records.map { record in
            guard record.id == recordID else {
                return record
            }

            var corrected = record
            corrected.correction = .excluded(reason: reason)
            corrected.modifiedAt = now
            return corrected
        }
        persist(synchronize: true)
    }

    func restore(recordID: SedentaryRecord.ID, now: Date = Date()) {
        records = records.map { record in
            guard record.id == recordID else {
                return record
            }

            var restored = record
            restored.correction = nil
            restored.modifiedAt = now
            return restored
        }
        persist(synchronize: true)
    }

    func requestPermissions() async {
        do {
            permissionState.notificationsAllowed = try await notifier.requestAuthorization()
        } catch {
            permissionState.notificationsAllowed = false
        }
    }

    func dailySummaries(days: Int, now: Date = Date()) -> [DailySedentarySummary] {
        SedentaryAnalytics.dailySummaries(records: records, endingOn: now, days: days)
    }

    private func apply(_ output: EngineOutput, at now: Date) {
        if !output.endedRecords.isEmpty {
            records = (output.endedRecords + records).deduplicatedByID()
        }

        lastNotificationReason = output.notificationReason
        snapshot = engine.snapshot(at: now)
        persist(synchronize: !output.endedRecords.isEmpty)

        guard output.shouldNotify else {
            return
        }

        Task {
            await notifier.scheduleSedentaryReminder(reason: output.notificationReason, seatedMinutes: snapshot.seatedMinutes)
        }
        scheduledReminderAt = nil
        scheduleNextReminderIfNeeded(now: now)
    }

    private var synchronizedState: StandUpDataState {
        StandUpDataState(
            settings: settings,
            settingsUpdatedAt: settingsUpdatedAt,
            records: records
        )
    }

    private func persist(synchronize: Bool = false) {
        let synchronizedState = synchronizedState
        try? storage.save(StandUpLocalState(synchronized: synchronizedState, session: engine.sessionState))
        if synchronize {
            sync.publish(synchronizedState)
        }
    }

    private func merge(_ state: StandUpDataState) {
        let merged = synchronizedState.merging(state)
        settings = merged.settings
        settingsUpdatedAt = merged.settingsUpdatedAt
        records = merged.records
        engine.update(settings: settings)
        persist()
    }

    private func scheduleNextReminderIfNeeded(now: Date) {
        guard let seatedMinutes = snapshot.seatedMinutes else {
            cancelScheduledReminder()
            return
        }

        let nextDate: Date?
        let reason: NotificationReason
        switch snapshot.phase {
        case .monitoring:
            nextDate = now.addingTimeInterval(TimeInterval(max(1, settings.sedentaryThresholdMinutes - seatedMinutes) * 60))
            reason = .thresholdReached
        case .overdue:
            nextDate = now.addingTimeInterval(TimeInterval(settings.repeatReminderMinutes * 60))
            reason = .repeatReminder
        case .ignored(let until):
            nextDate = until
            reason = .repeatReminder
        case .paused:
            nextDate = nil
            reason = .repeatReminder
        }

        guard let nextDate else {
            cancelScheduledReminder()
            return
        }

        if let scheduledReminderAt, abs(scheduledReminderAt.timeIntervalSince(nextDate)) < 30 {
            return
        }

        scheduledReminderAt = nextDate
        Task {
            await notifier.scheduleSedentaryReminder(at: nextDate, reason: reason)
        }
    }

    private func cancelScheduledReminder() {
        guard scheduledReminderAt != nil else {
            return
        }

        scheduledReminderAt = nil
        Task {
            await notifier.cancelSedentaryReminders()
        }
    }
}

struct PermissionState: Equatable {
    var notificationsAllowed: Bool?
    var motionAllowed: Bool?

    static let unknown = PermissionState(notificationsAllowed: nil, motionAllowed: nil)

    var canMonitor: Bool {
        motionAllowed != false
    }

    var canNotify: Bool {
        notificationsAllowed == true
    }
}

private extension Array where Element == SedentaryRecord {
    func deduplicatedByID() -> [SedentaryRecord] {
        var seen = Set<UUID>()
        return filter { record in
            seen.insert(record.id).inserted
        }
    }
}
