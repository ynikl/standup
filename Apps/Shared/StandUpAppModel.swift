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

    init(
        storage: StandUpStorage = LocalJSONStandUpStorage(),
        notifier: StandUpNotificationScheduling = LocalStandUpNotificationScheduler(),
        sync: StandUpSyncing = WatchConnectivityStandUpBridge()
    ) {
        self.storage = storage
        self.notifier = notifier
        self.sync = sync

        let persisted = (try? storage.load()) ?? .empty
        self.settings = persisted.settings
        self.records = persisted.records.sorted { $0.thresholdReachedAt > $1.thresholdReachedAt }
        self.permissionState = .unknown
        self.engine = SedentaryEngine(settings: persisted.settings)
        self.snapshot = engine.snapshot(at: Date())

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

    func updateThreshold(minutes: Int) {
        settings = StandUpSettings(
            sedentaryThresholdMinutes: minutes,
            activeClearMinutes: settings.activeClearMinutes,
            repeatReminderMinutes: settings.repeatReminderMinutes,
            activeWindow: settings.activeWindow
        )
        engine.update(settings: settings)
        persist()
    }

    func updateActiveWindow(startHour: Int, endHour: Int) {
        settings = StandUpSettings(
            sedentaryThresholdMinutes: settings.sedentaryThresholdMinutes,
            activeClearMinutes: settings.activeClearMinutes,
            repeatReminderMinutes: settings.repeatReminderMinutes,
            activeWindow: ActiveWindow(startMinuteOfDay: startHour * 60, endMinuteOfDay: endHour * 60)
        )
        engine.update(settings: settings)
        persist()
    }

    func correct(recordID: SedentaryRecord.ID, reason: CorrectionReason) {
        records = records.map { record in
            guard record.id == recordID else {
                return record
            }

            var corrected = record
            corrected.correction = .excluded(reason: reason)
            return corrected
        }
        persist()
    }

    func restore(recordID: SedentaryRecord.ID) {
        records = records.map { record in
            guard record.id == recordID else {
                return record
            }

            var restored = record
            restored.correction = nil
            return restored
        }
        persist()
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
        persist()

        guard output.shouldNotify else {
            return
        }

        Task {
            await notifier.scheduleSedentaryReminder(reason: output.notificationReason, seatedMinutes: snapshot.seatedMinutes)
        }
        scheduledReminderAt = nil
        scheduleNextReminderIfNeeded(now: now)
    }

    private func persist() {
        try? storage.save(StandUpPersistedState(settings: settings, records: records))
        sync.publish(settings: settings, records: records)
    }

    private func merge(_ state: StandUpPersistedState) {
        settings = state.settings
        records = (records + state.records)
            .deduplicatedByID()
            .sorted { $0.thresholdReachedAt > $1.thresholdReachedAt }
        engine.update(settings: settings)
        try? storage.save(StandUpPersistedState(settings: settings, records: records))
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
