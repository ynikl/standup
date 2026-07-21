import Foundation
import StandUpCore

#if canImport(UserNotifications)
import UserNotifications
#endif

struct SharedCheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SharedCheckFailure(message: message)
    }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw SharedCheckFailure(message: message)
    }
    return value
}

@main
@MainActor
struct StandUpSharedChecks {
    static func main() async throws {
        try checkMotionActivityClassification()
        print("PASS classifies only conclusive motion samples")
        try checkNormalizesMotionHistory()
        print("PASS normalizes motion history")
        try checkRestoresPersistedSession()
        print("PASS restores persisted session")
        try checkPersistsSessionAfterActivity()
        print("PASS persists session after activity")
        try checkPersistsOnlyStateChangingTicks()
        print("PASS persists only state-changing ticks")
        try checkPersistsOnlyChangedSettings()
        print("PASS persists only changed settings")
        try checkBuildsStableRequestsFromPlan()
        print("PASS builds stable requests from plan")
        try await checkReconcilesReminderPlan()
        print("PASS reconciles reminder plan")
        try await checkSurfacesReminderFailure()
        print("PASS surfaces reminder failure")
        try await checkProtectsUnreadableStorage()
        print("PASS protects unreadable storage")
        try await checkSurfacesSyncFailure()
        print("PASS surfaces sync failure")
        try checkReportsInvalidSyncPayload()
        print("PASS reports invalid sync payload")
        try await checkLatestReminderPlanWins()
        print("PASS latest reminder plan wins")
        try await checkThresholdTickPreservesPlannedReminder()
        print("PASS threshold tick preserves planned reminder")
        try await checkReviewOnlyModelNeverSchedulesReminders()
        print("PASS review-only model never schedules reminders")
        try await checkRetriesStorageLoad()
        print("PASS retries storage load")
        try await checkRetriesStorageSave()
        print("PASS retries storage save")
        try await checkRetriesSynchronization()
        print("PASS retries synchronization")
        try await checkRetriesReminderScheduling()
        print("PASS retries reminder scheduling")
        try await checkCoalescesConcurrentRetries()
        print("PASS coalesces concurrent retries")
        try await checkRetriesSyncActivation()
        print("PASS retries sync activation")
        try checkReportsSessionActivationFailure()
        print("PASS reports session activation failure")
        try checkBuildsMotionRecoveryBoundary()
        print("PASS builds motion recovery boundary")
        print("\nAll 23 shared checks passed")
    }

    private static func checkMotionActivityClassification() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try expect(
            MotionActivityClassifier.signal(for: MotionActivitySample(startedAt: now, stationary: true)) == .sedentary,
            "stationary sample should start sedentary tracking"
        )
        try expect(
            MotionActivityClassifier.signal(for: MotionActivitySample(startedAt: now, walking: true)) == .active,
            "walking sample should count as active"
        )
        try expect(
            MotionActivityClassifier.signal(for: MotionActivitySample(startedAt: now, unknown: true)) == nil,
            "unknown sample should be inconclusive rather than unavailable"
        )
        try expect(
            MotionActivityClassifier.signal(for: MotionActivitySample(startedAt: now, automotive: true)) == nil,
            "automotive-only sample should not masquerade as a sensor failure"
        )
    }

    private static func checkNormalizesMotionHistory() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            MotionActivitySample(startedAt: start.addingTimeInterval(120), walking: true),
            MotionActivitySample(startedAt: start.addingTimeInterval(-60), stationary: true),
            MotionActivitySample(startedAt: start.addingTimeInterval(60), stationary: true),
            MotionActivitySample(startedAt: start.addingTimeInterval(180), unknown: true)
        ]

        let observations = MotionActivityClassifier.normalizedObservations(from: samples, since: start)

        try expect(observations.count == 2, "history should omit inconclusive and consecutive duplicate samples")
        try expect(observations[0] == MotionActivityObservation(signal: .sedentary, startedAt: start), "first sample should be clamped to recovery start")
        try expect(observations[1] == MotionActivityObservation(signal: .active, startedAt: start.addingTimeInterval(120)), "history should be chronological")
    }

    private static func checkRestoresPersistedSession() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        var engine = SedentaryEngine(settings: settings)
        _ = engine.ingest(.activity(.sedentary), at: now.addingTimeInterval(-10 * 60))
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let storage = MemoryStorage(
            state: StandUpLocalState(synchronized: synchronized, session: engine.sessionState)
        )

        let model = StandUpAppModel(
            storage: storage,
            notifier: NoopNotifier(),
            sync: MemorySync(),
            now: now
        )

        try expect(model.snapshot.seatedMinutes == 10, "restored seated duration")
    }

    private static func checkPersistsSessionAfterActivity() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let storage = MemoryStorage(state: StandUpLocalState(synchronized: synchronized))
        let model = StandUpAppModel(
            storage: storage,
            notifier: NoopNotifier(),
            sync: MemorySync(),
            now: now
        )

        model.ingest(activity: .sedentary, now: now)

        try expect(storage.state.session.seatedSince == now, "activity should persist session start")
    }

    private static func checkBuildsMotionRecoveryBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activeStart = calendar.startOfDay(for: now)
        let lastActivityAt = now.addingTimeInterval(-15 * 60)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let storage = MemoryStorage(
            state: StandUpLocalState(
                synchronized: StandUpDataState(settings: settings, settingsUpdatedAt: now, records: []),
                session: SedentarySessionState(lastActivityAt: lastActivityAt)
            )
        )
        let model = StandUpAppModel(
            storage: storage,
            notifier: NoopNotifier(),
            sync: MemorySync(),
            managesReminders: false,
            now: now
        )

        try expect(model.motionRecoveryStart(now: now, calendar: calendar) == lastActivityAt, "persisted activity time should be the recovery cursor")

        let freshModel = StandUpAppModel(
            storage: MemoryStorage(
                state: StandUpLocalState(
                    synchronized: StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
                )
            ),
            notifier: NoopNotifier(),
            sync: MemorySync(),
            managesReminders: false,
            now: now
        )
        try expect(freshModel.motionRecoveryStart(now: now, calendar: calendar) == activeStart, "fresh monitoring should recover from the active-window start")
    }

    private static func checkPersistsOnlyStateChangingTicks() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let storage = MemoryStorage(state: StandUpLocalState(synchronized: synchronized))
        let model = StandUpAppModel(
            storage: storage,
            notifier: NoopNotifier(),
            sync: MemorySync(),
            now: now
        )

        model.ingest(activity: .sedentary, now: now)
        try expect(storage.saveCount == 1, "session start should persist")

        model.refresh(now: now.addingTimeInterval(60))
        try expect(storage.saveCount == 1, "unchanged tick should not persist")

        model.refresh(now: now.addingTimeInterval(45 * 60))
        try expect(storage.saveCount == 2, "threshold tick should persist")
        try expect(
            storage.state.session.thresholdReachedAt == now.addingTimeInterval(45 * 60),
            "threshold transition should be recoverable"
        )
    }

    private static func checkPersistsOnlyChangedSettings() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let storage = MemoryStorage(state: StandUpLocalState(synchronized: synchronized))
        let sync = MemorySync()
        let model = StandUpAppModel(
            storage: storage,
            notifier: NoopNotifier(),
            sync: sync,
            now: now
        )

        model.updateThreshold(minutes: 46, now: now.addingTimeInterval(1))
        model.updateActiveWindow(startHour: 0, endHour: 24, now: now.addingTimeInterval(2))

        try expect(storage.saveCount == 0, "normalized unchanged settings should not persist")
        try expect(sync.published.isEmpty, "normalized unchanged settings should not sync")

        model.updateThreshold(minutes: 60, now: now.addingTimeInterval(3))

        try expect(model.settings.sedentaryThresholdMinutes == 60, "changed threshold should update")
        try expect(storage.saveCount == 1, "changed threshold should persist once")
        try expect(sync.published.count == 1, "changed threshold should sync once")
    }

    private static func checkBuildsStableRequestsFromPlan() throws {
        #if canImport(UserNotifications)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = ReminderPlan(reminders: [
            PlannedReminder(
                id: "threshold-1",
                deliveryDate: now.addingTimeInterval(60),
                reason: .thresholdReached
            ),
            PlannedReminder(
                id: "repeat-1",
                deliveryDate: now.addingTimeInterval(120),
                reason: .repeatReminder
            )
        ])

        let requests = LocalStandUpNotificationScheduler().requests(for: plan, now: now)

        try expect(
            requests.map(\.identifier) == ["sedentary-reminder-threshold-1", "sedentary-reminder-repeat-1"],
            "stable notification identifiers"
        )
        let intervals = try requests.map { request in
            try require(
                request.trigger as? UNTimeIntervalNotificationTrigger,
                "time interval notification trigger"
            ).timeInterval
        }
        try expect(intervals == [60, 120], "notification delivery intervals")
        #endif
    }

    private static func checkReconcilesReminderPlan() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let storage = MemoryStorage(state: StandUpLocalState(synchronized: synchronized))
        let notifier = RecordingNotifier()
        let model = StandUpAppModel(
            storage: storage,
            notifier: notifier,
            sync: MemorySync(),
            now: now
        )

        model.ingest(activity: .sedentary, now: now)
        await model.waitForReminderReconciliation()

        let plan = try require(notifier.plans.last, "reconciled reminder plan")
        try expect(
            plan.reminders.first?.deliveryDate == now.addingTimeInterval(45 * 60),
            "model should execute core reminder plan"
        )
    }

    private static func checkSurfacesReminderFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let model = StandUpAppModel(
            storage: MemoryStorage(state: StandUpLocalState(synchronized: synchronized)),
            notifier: FailingNotifier(),
            sync: MemorySync(),
            now: now
        )

        model.ingest(activity: .sedentary, now: now)
        await model.waitForReminderReconciliation()

        try expect(
            model.operationalError?.contains("Unable to update reminders") == true,
            "notification failure should be visible"
        )
    }

    private static func checkProtectsUnreadableStorage() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let storage = FailingLoadStorage()
        let model = StandUpAppModel(
            storage: storage,
            notifier: NoopNotifier(),
            sync: MemorySync(),
            now: now
        )

        try expect(
            model.operationalError?.contains("Unable to load local data") == true,
            "load failure should be visible"
        )
        model.refresh(now: now)
        await model.waitForReminderReconciliation()
        try expect(storage.saveCount == 0, "refresh must not overwrite unreadable storage")
        try expect(
            model.operationalError?.contains("Unable to load local data") == true,
            "notification reconciliation must not hide a storage error"
        )

        model.updateThreshold(minutes: 60, now: now)
        try expect(storage.saveCount == 0, "explicit setting change must not overwrite unreadable storage")
        try expect(
            model.operationalError?.contains("Unable to load local data") == true,
            "explicit setting change must preserve the load error"
        )
        await model.retryOperationalWork(now: now)
        try expect(storage.saveCount == 0, "failed load retry must not write storage")
    }

    private static func checkSurfacesSyncFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let model = StandUpAppModel(
            storage: MemoryStorage(state: StandUpLocalState(synchronized: synchronized)),
            notifier: NoopNotifier(),
            sync: FailingSync(),
            now: now
        )

        model.updateThreshold(minutes: 60, now: now.addingTimeInterval(1))
        await model.waitForReminderReconciliation()

        try expect(
            model.operationalError?.contains("Unable to sync data") == true,
            "sync failure should be visible"
        )
    }

    private static func checkReportsInvalidSyncPayload() throws {
        let bridge = WatchConnectivityStandUpBridge()
        var receivedError = false
        bridge.onError = { _ in
            receivedError = true
        }

        bridge.receive(Data("invalid-state".utf8))

        try expect(receivedError, "invalid synchronization payload should report an error")
    }

    private static func checkLatestReminderPlanWins() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let notifier = SlowFirstNotifier()
        let model = StandUpAppModel(
            storage: MemoryStorage(state: StandUpLocalState(synchronized: synchronized)),
            notifier: notifier,
            sync: MemorySync(),
            now: now
        )

        model.ingest(activity: .sedentary, now: now)
        await notifier.waitUntilFirstCallStarts()
        model.ingest(activity: .active, now: now.addingTimeInterval(1))
        await model.waitForReminderReconciliation()

        try expect(notifier.completedPlans.last == .empty, "latest empty plan should be applied last")
    }

    private static func checkThresholdTickPreservesPlannedReminder() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let notifier = RecordingNotifier()
        let model = StandUpAppModel(
            storage: MemoryStorage(state: StandUpLocalState(synchronized: synchronized)),
            notifier: notifier,
            sync: MemorySync(),
            now: now
        )

        model.ingest(activity: .sedentary, now: now)
        await model.waitForReminderReconciliation()
        model.refresh(now: now.addingTimeInterval(45 * 60))
        await model.waitForReminderReconciliation()

        try expect(notifier.plans.count == 1, "threshold tick should not replace the pending plan")
        let plan = try require(notifier.plans.last, "initial reminder plan")
        try expect(
            plan.reminders.first?.reason == .thresholdReached,
            "pending threshold reminder should be preserved"
        )
        try expect(plan.reminders.count <= 60, "adapter plan should preserve the 60 request cap")
    }

    private static func checkReviewOnlyModelNeverSchedulesReminders() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let notifier = RecordingNotifier()
        let sync = MemorySync()
        let model = StandUpAppModel(
            storage: MemoryStorage(state: StandUpLocalState(synchronized: synchronized)),
            notifier: notifier,
            sync: sync,
            managesReminders: false,
            now: now
        )

        model.updateThreshold(minutes: 60, now: now.addingTimeInterval(1))
        sync.onReceive?(
            StandUpDataState(
                settings: StandUpSettings(
                    sedentaryThresholdMinutes: 75,
                    activeWindow: ActiveWindow(startMinuteOfDay: 8 * 60, endMinuteOfDay: 20 * 60)
                ),
                settingsUpdatedAt: now.addingTimeInterval(2),
                records: []
            )
        )
        await model.waitForReminderReconciliation()

        try expect(model.settings.sedentaryThresholdMinutes == 75, "review-only model should merge settings")
        try expect(notifier.plans.isEmpty, "review-only model must not replace reminders")
    }

    private static func checkRetriesStorageLoad() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recoveredSettings = StandUpSettings(
            sedentaryThresholdMinutes: 75,
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let storage = RecoveringLoadStorage(
            recoveredState: StandUpLocalState(
                synchronized: StandUpDataState(
                    settings: recoveredSettings,
                    settingsUpdatedAt: now,
                    records: []
                )
            )
        )
        let sync = MemorySync()
        let model = StandUpAppModel(
            storage: storage,
            notifier: NoopNotifier(),
            sync: sync,
            managesReminders: false,
            now: now
        )

        try expect(model.operationalError?.contains("Unable to load local data") == true, "load failure should be visible before retry")
        model.ingest(activity: .sedentary, now: now)
        model.updateThreshold(minutes: 90, now: now.addingTimeInterval(1))
        sync.onReceive?(
            StandUpDataState(
                settings: StandUpSettings(
                    sedentaryThresholdMinutes: 85,
                    activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
                ),
                settingsUpdatedAt: now.addingTimeInterval(0.5),
                records: []
            )
        )
        try expect(storage.saveCount == 0, "edits after load failure must not overwrite unreadable data")
        try expect(model.operationalError?.contains("Unable to load local data") == true, "edits must preserve the load error")
        await model.retryOperationalWork(now: now.addingTimeInterval(60))

        try expect(model.settings.sedentaryThresholdMinutes == 90, "load retry should preserve newer synced settings")
        try expect(model.snapshot.seatedMinutes == 1, "load retry should preserve the current session")
        try expect(storage.saveCount == 1, "load retry should persist after a successful read")
        try expect(storage.savedState?.synchronized.settings.sedentaryThresholdMinutes == 90, "load retry should save merged settings")
        try expect(storage.savedState?.session.seatedSince == now, "load retry should save the current session")
        try expect(sync.published.last?.settings.sedentaryThresholdMinutes == 90, "load retry should publish merged settings")
        try expect(model.operationalError == nil, "load retry should clear the error")
    }

    private static func checkRetriesStorageSave() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let storage = RecoveringSaveStorage(
            state: StandUpLocalState(
                synchronized: StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
            )
        )
        let sync = MemorySync()
        let model = StandUpAppModel(
            storage: storage,
            notifier: NoopNotifier(),
            sync: sync,
            managesReminders: false,
            now: now
        )

        model.updateThreshold(minutes: 60, now: now.addingTimeInterval(1))
        try expect(model.operationalError?.contains("Unable to save local data") == true, "save failure should be visible before retry")
        await model.retryOperationalWork(now: now.addingTimeInterval(2))

        try expect(storage.saveAttempts == 2, "save retry should make one new attempt")
        try expect(storage.state.synchronized.settings.sedentaryThresholdMinutes == 60, "save retry should persist current settings")
        try expect(sync.published.last?.settings.sedentaryThresholdMinutes == 60, "save retry should publish recovered settings")
        try expect(model.operationalError == nil, "save retry should clear the error")
    }

    private static func checkRetriesSynchronization() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let storage = MemoryStorage(
            state: StandUpLocalState(
                synchronized: StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
            )
        )
        let sync = RecoveringSync()
        let model = StandUpAppModel(
            storage: storage,
            notifier: NoopNotifier(),
            sync: sync,
            managesReminders: false,
            now: now
        )

        model.updateThreshold(minutes: 60, now: now.addingTimeInterval(1))
        try expect(model.operationalError?.contains("Unable to sync data") == true, "sync failure should be visible before retry")
        sync.onReceive?(
            StandUpDataState(
                settings: .default,
                settingsUpdatedAt: now.addingTimeInterval(-1),
                records: []
            )
        )
        try expect(model.operationalError?.contains("Unable to sync data") == true, "incoming state must not clear a pending publish failure")
        let saveCountBeforeRetry = storage.saveCount
        await model.retryOperationalWork(now: now.addingTimeInterval(2))

        try expect(sync.publishAttempts == 2, "sync retry should make one new attempt")
        try expect(sync.published.last?.settings.sedentaryThresholdMinutes == 60, "sync retry should publish current settings")
        try expect(storage.saveCount == saveCountBeforeRetry, "sync retry must not rewrite local storage")
        try expect(model.operationalError == nil, "sync retry should clear the error")
    }

    private static func checkRetriesReminderScheduling() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let notifier = RecoveringNotifier()
        let model = StandUpAppModel(
            storage: MemoryStorage(
                state: StandUpLocalState(
                    synchronized: StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
                )
            ),
            notifier: notifier,
            sync: MemorySync(),
            now: now
        )

        model.ingest(activity: .sedentary, now: now)
        await model.waitForReminderReconciliation()
        try expect(model.operationalError?.contains("Unable to update reminders") == true, "reminder failure should be visible before retry")

        await model.retryOperationalWork(now: now.addingTimeInterval(1))

        try expect(notifier.replaceAttempts == 2, "reminder retry should make one new attempt")
        try expect(notifier.plans.count == 1, "reminder retry should apply the replacement plan")
        try expect(model.operationalError == nil, "reminder retry should clear the error")
    }

    private static func checkCoalescesConcurrentRetries() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let notifier = BlockingRetryNotifier()
        let model = StandUpAppModel(
            storage: MemoryStorage(
                state: StandUpLocalState(
                    synchronized: StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
                )
            ),
            notifier: notifier,
            sync: MemorySync(),
            now: now
        )

        model.ingest(activity: .sedentary, now: now)
        await model.waitForReminderReconciliation()

        let retryTask = Task {
            await model.retryOperationalWork(now: now.addingTimeInterval(1))
        }
        await notifier.waitUntilRetryStarts()
        try expect(model.isRetryingOperationalWork, "model should expose retry progress")

        await model.retryOperationalWork(now: now.addingTimeInterval(2))
        try expect(notifier.replaceAttempts == 2, "concurrent retry must not duplicate work")

        notifier.releaseRetry()
        await retryTask.value
        try expect(!model.isRetryingOperationalWork, "retry progress should reset")
        try expect(model.operationalError == nil, "completed retry should clear the error")
    }

    private static func checkRetriesSyncActivation() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(
            activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
        )
        let sync = BlockingActivationSync()
        let model = StandUpAppModel(
            storage: MemoryStorage(
                state: StandUpLocalState(
                    synchronized: StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
                )
            ),
            notifier: NoopNotifier(),
            sync: sync,
            managesReminders: false,
            now: now
        )

        try expect(model.operationalError?.contains("Unable to receive synced data") == true, "activation failure should be visible before retry")
        let retryTask = Task {
            await model.retryOperationalWork(now: now)
        }
        await sync.waitUntilRetryStarts()

        try expect(model.isRetryingOperationalWork, "activation retry should keep progress visible until completion")
        await model.retryOperationalWork(now: now.addingTimeInterval(1))
        try expect(sync.activationAttempts == 2, "sync retry should reactivate once")

        sync.completeRetry()
        await retryTask.value

        try expect(model.operationalError == nil, "successful activation retry should clear the error")
        try expect(!model.isRetryingOperationalWork, "activation retry should clear progress after completion")
    }

    private static func checkReportsSessionActivationFailure() throws {
        let bridge = WatchConnectivityStandUpBridge()
        var receivedError = false
        var receivedActivation = false
        bridge.onError = { _ in
            receivedError = true
        }
        bridge.onActivation = {
            receivedActivation = true
        }

        bridge.handleActivation(error: ExpectedSyncError())

        try expect(receivedError, "session activation failure should be reported")
        try expect(!receivedActivation, "session activation failure must not report success")

        bridge.handleActivation(error: nil)

        try expect(receivedActivation, "session activation success should be reported")
    }
}

private final class MemoryStorage: StandUpStorage {
    var state: StandUpLocalState
    var saveCount = 0

    init(state: StandUpLocalState) {
        self.state = state
    }

    func load() throws -> StandUpLocalState {
        state
    }

    func save(_ state: StandUpLocalState) throws {
        saveCount += 1
        self.state = state
    }
}

private struct ExpectedStorageError: Error {}

private final class FailingLoadStorage: StandUpStorage {
    var saveCount = 0

    func load() throws -> StandUpLocalState {
        throw ExpectedStorageError()
    }

    func save(_ state: StandUpLocalState) throws {
        saveCount += 1
    }
}

private final class RecoveringLoadStorage: StandUpStorage {
    let recoveredState: StandUpLocalState
    var loadAttempts = 0
    var saveCount = 0
    var savedState: StandUpLocalState?

    init(recoveredState: StandUpLocalState) {
        self.recoveredState = recoveredState
    }

    func load() throws -> StandUpLocalState {
        loadAttempts += 1
        if loadAttempts == 1 {
            throw ExpectedStorageError()
        }
        return recoveredState
    }

    func save(_ state: StandUpLocalState) throws {
        saveCount += 1
        savedState = state
    }
}

private final class RecoveringSaveStorage: StandUpStorage {
    var state: StandUpLocalState
    var saveAttempts = 0

    init(state: StandUpLocalState) {
        self.state = state
    }

    func load() throws -> StandUpLocalState {
        state
    }

    func save(_ state: StandUpLocalState) throws {
        saveAttempts += 1
        if saveAttempts == 1 {
            throw ExpectedStorageError()
        }
        self.state = state
    }
}

@MainActor
private struct NoopNotifier: StandUpNotificationScheduling {
    func requestAuthorization() async throws -> Bool { true }
    func replaceSedentaryReminders(with plan: ReminderPlan) async throws {}
    func cancelSedentaryReminders() async {}
}

@MainActor
private final class RecordingNotifier: StandUpNotificationScheduling {
    var plans: [ReminderPlan] = []

    func requestAuthorization() async throws -> Bool { true }

    func replaceSedentaryReminders(with plan: ReminderPlan) async throws {
        plans.append(plan)
    }

    func cancelSedentaryReminders() async {}
}

private struct ExpectedNotificationError: Error {}

@MainActor
private final class RecoveringNotifier: StandUpNotificationScheduling {
    var replaceAttempts = 0
    var plans: [ReminderPlan] = []

    func requestAuthorization() async throws -> Bool { true }

    func replaceSedentaryReminders(with plan: ReminderPlan) async throws {
        replaceAttempts += 1
        if replaceAttempts == 1 {
            throw ExpectedNotificationError()
        }
        plans.append(plan)
    }

    func cancelSedentaryReminders() async {}
}

@MainActor
private final class BlockingRetryNotifier: StandUpNotificationScheduling {
    var replaceAttempts = 0

    private var retryStarted = false
    private var retryStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func requestAuthorization() async throws -> Bool { true }

    func replaceSedentaryReminders(with plan: ReminderPlan) async throws {
        replaceAttempts += 1
        if replaceAttempts == 1 {
            throw ExpectedNotificationError()
        }

        retryStarted = true
        let waiters = retryStartedWaiters
        retryStartedWaiters.removeAll()
        waiters.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func cancelSedentaryReminders() async {}

    func waitUntilRetryStarts() async {
        guard !retryStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            retryStartedWaiters.append(continuation)
        }
    }

    func releaseRetry() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private struct FailingNotifier: StandUpNotificationScheduling {
    func requestAuthorization() async throws -> Bool { true }

    func replaceSedentaryReminders(with plan: ReminderPlan) async throws {
        throw ExpectedNotificationError()
    }

    func cancelSedentaryReminders() async {}
}

@MainActor
private final class SlowFirstNotifier: StandUpNotificationScheduling {
    var completedPlans: [ReminderPlan] = []

    private var firstCallStarted = false
    private var firstCallWaiters: [CheckedContinuation<Void, Never>] = []

    func requestAuthorization() async throws -> Bool { true }

    func replaceSedentaryReminders(with plan: ReminderPlan) async throws {
        if !firstCallStarted {
            firstCallStarted = true
            let waiters = firstCallWaiters
            firstCallWaiters.removeAll()
            waiters.forEach { $0.resume() }
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                // Cancellation is expected when a newer reminder plan supersedes this one.
            }
        }
        completedPlans.append(plan)
    }

    func cancelSedentaryReminders() async {}

    func waitUntilFirstCallStarts() async {
        guard !firstCallStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            firstCallWaiters.append(continuation)
        }
    }
}

@MainActor
private final class MemorySync: StandUpSyncing {
    var onReceive: ((StandUpDataState) -> Void)?
    var onError: ((Error) -> Void)?
    var onActivation: (() -> Void)?
    var published: [StandUpDataState] = []

    func activate() {}
    func retryActivation() async { activate() }

    func publish(_ state: StandUpDataState) throws {
        published.append(state)
    }
}

private struct ExpectedSyncError: Error {}

@MainActor
private final class RecoveringSync: StandUpSyncing {
    var onReceive: ((StandUpDataState) -> Void)?
    var onError: ((Error) -> Void)?
    var onActivation: (() -> Void)?
    var publishAttempts = 0
    var published: [StandUpDataState] = []

    func activate() {}
    func retryActivation() async { activate() }

    func publish(_ state: StandUpDataState) throws {
        publishAttempts += 1
        if publishAttempts == 1 {
            throw ExpectedSyncError()
        }
        published.append(state)
    }
}

@MainActor
private final class BlockingActivationSync: StandUpSyncing {
    var onReceive: ((StandUpDataState) -> Void)?
    var onError: ((Error) -> Void)?
    var onActivation: (() -> Void)?
    var activationAttempts = 0

    private var retryStarted = false
    private var retryStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func activate() {
        activationAttempts += 1
        if activationAttempts == 1 {
            onError?(ExpectedSyncError())
        } else {
            markRetryStarted()
        }
    }

    func retryActivation() async {
        activationAttempts += 1
        markRetryStarted()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func publish(_ state: StandUpDataState) throws {}

    func waitUntilRetryStarts() async {
        guard !retryStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            retryStartedWaiters.append(continuation)
        }
    }

    func completeRetry() {
        onActivation?()
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    private func markRetryStarted() {
        retryStarted = true
        let waiters = retryStartedWaiters
        retryStartedWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

@MainActor
private final class FailingSync: StandUpSyncing {
    var onReceive: ((StandUpDataState) -> Void)?
    var onError: ((Error) -> Void)?
    var onActivation: (() -> Void)?

    func activate() {}
    func retryActivation() async { activate() }

    func publish(_ state: StandUpDataState) throws {
        throw ExpectedSyncError()
    }
}
