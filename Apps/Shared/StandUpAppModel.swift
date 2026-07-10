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
    private var lastReminderPlan: ReminderPlan?
    private var settingsUpdatedAt: Date
    private var persistenceEnabled: Bool
    private var persistenceError: String?
    private var syncError: String?
    private var notificationError: String?

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
        self.engine = SedentaryEngine(settings: persisted.synchronized.settings, sessionState: persisted.session)
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
        apply(engine.ingest(.tick, at: now), at: now)
    }

    func ingest(activity: ActivitySignal, now: Date = Date()) {
        permissionState.motionAllowed = activity == .unavailable ? false : true
        apply(engine.ingest(.activity(activity), at: now), at: now)
    }

    func ignore(_ duration: IgnoreDuration, now: Date = Date()) {
        apply(engine.ingest(.ignore(duration), at: now), at: now)
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
        snapshot = engine.snapshot(at: now)
        persist(synchronize: true, recoverStorage: true)
        reconcileReminders(now: now)
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

    private func apply(_ output: EngineOutput, at now: Date) {
        if !output.endedRecords.isEmpty {
            records = (output.endedRecords + records).deduplicatedByID()
        }

        lastNotificationReason = output.notificationReason
        snapshot = engine.snapshot(at: now)
        persist(synchronize: !output.endedRecords.isEmpty)
        reconcileReminders(now: now, immediateReason: output.shouldNotify ? output.notificationReason : nil)
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

    private func reconcileReminders(now: Date, immediateReason: NotificationReason? = nil) {
        var plan = engine.reminderPlan(at: now)
        if let immediateReason {
            plan.reminders.insert(
                PlannedReminder(
                    id: "immediate-\(immediateReason.rawValue)-\(Int(now.timeIntervalSince1970))",
                    deliveryDate: now,
                    reason: immediateReason
                ),
                at: 0
            )
        }

        guard plan != lastReminderPlan else {
            return
        }

        lastReminderPlan = plan
        Task {
            do {
                try await notifier.replaceSedentaryReminders(with: plan)
                notificationError = nil
                refreshOperationalError()
            } catch {
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
