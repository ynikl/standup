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
    @Published private(set) var operationalError: String?

    private var engine: SedentaryEngine
    private let storage: StandUpStorage
    private let notifier: StandUpNotificationScheduling
    private let sync: StandUpSyncing
    private let managesReminders: Bool
    private var lastReminderPlan: ReminderPlan?
    private var reminderReconciliationTask: Task<Void, Never>?
    private var reminderReconciliationGeneration = 0
    private var settingsUpdatedAt: Date
    private var persistenceEnabled: Bool
    private var persistenceError: String?
    private var syncError: String?
    private var notificationError: String?

    init(
        storage: StandUpStorage? = nil,
        notifier: StandUpNotificationScheduling? = nil,
        sync: StandUpSyncing? = nil,
        managesReminders: Bool = true,
        now: Date = Date()
    ) {
        let storage = storage ?? LocalJSONStandUpStorage()
        let notifier = notifier ?? LocalStandUpNotificationScheduler()
        let sync = sync ?? WatchConnectivityStandUpBridge()
        self.storage = storage
        self.notifier = notifier
        self.sync = sync
        self.managesReminders = managesReminders

        let persisted: StandUpLocalState
        let loadError: String?
        do {
            persisted = try storage.load()
            self.persistenceEnabled = true
            loadError = nil
        } catch {
            persisted = StandUpLocalState(
                synchronized: StandUpDataState(
                    settings: .default,
                    settingsUpdatedAt: Date(timeIntervalSince1970: 0),
                    records: []
                )
            )
            self.persistenceEnabled = false
            loadError = "Unable to load local data: \(error.localizedDescription)"
        }
        self.settings = persisted.synchronized.settings
        self.settingsUpdatedAt = persisted.synchronized.settingsUpdatedAt
        self.records = persisted.synchronized.records.sorted { $0.thresholdReachedAt > $1.thresholdReachedAt }
        self.permissionState = .unknown
        self.persistenceError = loadError
        self.syncError = nil
        self.notificationError = nil
        self.operationalError = loadError
        self.engine = SedentaryEngine(
            settings: persisted.synchronized.settings,
            sessionState: persisted.session,
            restoredAt: now
        )
        self.snapshot = engine.snapshot(at: now)

        self.sync.onReceive = { [weak self] state in
            self?.syncError = nil
            self?.refreshOperationalError()
            self?.merge(state)
        }
        self.sync.onError = { [weak self] error in
            self?.syncError = "Unable to receive synced data: \(error.localizedDescription)"
            self?.refreshOperationalError()
        }
        self.sync.activate()
    }

    func refresh(now: Date = Date()) {
        if lastReminderPlan == nil {
            reconcileReminders(now: now)
        }
        let previousSession = engine.sessionState
        let output = engine.ingest(.tick, at: now)
        apply(
            output,
            at: now,
            sessionChanged: previousSession != engine.sessionState,
            reconcilePlan: false
        )
    }

    func ingest(activity: ActivitySignal, now: Date = Date()) {
        permissionState.motionAllowed = activity == .unavailable ? false : true
        let previousSession = engine.sessionState
        let output = engine.ingest(.activity(activity), at: now)
        apply(
            output,
            at: now,
            sessionChanged: previousSession != engine.sessionState,
            reconcilePlan: !output.shouldNotify
        )
    }

    func ignore(_ duration: IgnoreDuration, now: Date = Date()) {
        let previousSession = engine.sessionState
        let output = engine.ingest(.ignore(duration), at: now)
        apply(output, at: now, sessionChanged: previousSession != engine.sessionState)
    }

    func updateThreshold(minutes: Int, now: Date = Date()) {
        let updatedSettings = StandUpSettings(
            sedentaryThresholdMinutes: minutes,
            activeClearMinutes: settings.activeClearMinutes,
            repeatReminderMinutes: settings.repeatReminderMinutes,
            activeWindow: settings.activeWindow
        )
        guard updatedSettings != settings else {
            return
        }
        settings = updatedSettings
        settingsUpdatedAt = now
        engine.update(settings: settings)
        snapshot = engine.snapshot(at: now)
        persist(synchronize: true, recoverStorage: true)
        reconcileReminders(now: now)
    }

    func updateActiveWindow(startHour: Int, endHour: Int, now: Date = Date()) {
        let updatedSettings = StandUpSettings(
            sedentaryThresholdMinutes: settings.sedentaryThresholdMinutes,
            activeClearMinutes: settings.activeClearMinutes,
            repeatReminderMinutes: settings.repeatReminderMinutes,
            activeWindow: ActiveWindow(startMinuteOfDay: startHour * 60, endMinuteOfDay: endHour * 60)
        )
        guard updatedSettings != settings else {
            return
        }
        settings = updatedSettings
        settingsUpdatedAt = now
        engine.update(settings: settings)
        snapshot = engine.snapshot(at: now)
        persist(synchronize: true, recoverStorage: true)
        reconcileReminders(now: now)
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
        persist(synchronize: true, recoverStorage: true)
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
        persist(synchronize: true, recoverStorage: true)
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

    func waitForReminderReconciliation() async {
        await reminderReconciliationTask?.value
    }

    private func apply(
        _ output: EngineOutput,
        at now: Date,
        sessionChanged: Bool,
        reconcilePlan: Bool = true
    ) {
        if !output.endedRecords.isEmpty {
            records = (output.endedRecords + records).deduplicatedByID()
        }

        lastNotificationReason = output.notificationReason
        snapshot = engine.snapshot(at: now)
        if sessionChanged || !output.endedRecords.isEmpty {
            persist(synchronize: !output.endedRecords.isEmpty)
        }
        if reconcilePlan {
            reconcileReminders(now: now)
        }
    }

    private var synchronizedState: StandUpDataState {
        StandUpDataState(
            settings: settings,
            settingsUpdatedAt: settingsUpdatedAt,
            records: records
        )
    }

    private func persist(synchronize: Bool = false, recoverStorage: Bool = false) {
        if recoverStorage {
            persistenceEnabled = true
        }

        guard persistenceEnabled else {
            return
        }

        let synchronizedState = synchronizedState
        do {
            try storage.save(StandUpLocalState(synchronized: synchronizedState, session: engine.sessionState))
            persistenceError = nil
            refreshOperationalError()
        } catch {
            persistenceEnabled = false
            persistenceError = "Unable to save local data: \(error.localizedDescription)"
            refreshOperationalError()
            return
        }

        if synchronize {
            do {
                try sync.publish(synchronizedState)
                syncError = nil
                refreshOperationalError()
            } catch {
                syncError = "Unable to sync data: \(error.localizedDescription)"
                refreshOperationalError()
            }
        }
    }

    private func merge(_ state: StandUpDataState) {
        let merged = synchronizedState.merging(state)
        settings = merged.settings
        settingsUpdatedAt = merged.settingsUpdatedAt
        records = merged.records
        engine.update(settings: settings)
        snapshot = engine.snapshot(at: Date())
        persist()
        reconcileReminders(now: Date())
    }

    private func reconcileReminders(now: Date) {
        guard managesReminders else {
            return
        }

        let plan = engine.reminderPlan(at: now)
        guard plan != lastReminderPlan else {
            return
        }

        lastReminderPlan = plan
        reminderReconciliationGeneration += 1
        let generation = reminderReconciliationGeneration
        let previousTask = reminderReconciliationTask
        previousTask?.cancel()
        reminderReconciliationTask = Task { [weak self, notifier] in
            await previousTask?.value
            guard !Task.isCancelled else {
                return
            }

            do {
                try await notifier.replaceSedentaryReminders(with: plan)
                guard let self, reminderReconciliationGeneration == generation else {
                    return
                }
                notificationError = nil
                refreshOperationalError()
            } catch {
                guard let self, reminderReconciliationGeneration == generation else {
                    return
                }
                lastReminderPlan = nil
                notificationError = "Unable to update reminders: \(error.localizedDescription)"
                refreshOperationalError()
            }
        }
    }

    private func refreshOperationalError() {
        operationalError = persistenceError ?? syncError ?? notificationError
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
