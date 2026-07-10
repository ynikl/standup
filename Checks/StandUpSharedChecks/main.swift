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
        try checkRestoresPersistedSession()
        print("PASS restores persisted session")
        try checkPersistsSessionAfterActivity()
        print("PASS persists session after activity")
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
        print("\nAll 8 shared checks passed")
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
        await Task.yield()

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
        await Task.yield()

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
        await Task.yield()
        try expect(storage.saveCount == 0, "refresh must not overwrite unreadable storage")
        try expect(
            model.operationalError?.contains("Unable to load local data") == true,
            "notification reconciliation must not hide a storage error"
        )

        model.updateThreshold(minutes: 60, now: now)
        try expect(storage.saveCount == 1, "explicit setting change should restore persistence")
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
        await Task.yield()

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
}

private final class MemoryStorage: StandUpStorage {
    var state: StandUpLocalState

    init(state: StandUpLocalState) {
        self.state = state
    }

    func load() throws -> StandUpLocalState {
        state
    }

    func save(_ state: StandUpLocalState) throws {
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
private struct FailingNotifier: StandUpNotificationScheduling {
    func requestAuthorization() async throws -> Bool { true }

    func replaceSedentaryReminders(with plan: ReminderPlan) async throws {
        throw ExpectedNotificationError()
    }

    func cancelSedentaryReminders() async {}
}

@MainActor
private final class MemorySync: StandUpSyncing {
    var onReceive: ((StandUpDataState) -> Void)?
    var onError: ((Error) -> Void)?
    var published: [StandUpDataState] = []

    func activate() {}

    func publish(_ state: StandUpDataState) throws {
        published.append(state)
    }
}

private struct ExpectedSyncError: Error {}

@MainActor
private final class FailingSync: StandUpSyncing {
    var onReceive: ((StandUpDataState) -> Void)?
    var onError: ((Error) -> Void)?

    func activate() {}

    func publish(_ state: StandUpDataState) throws {
        throw ExpectedSyncError()
    }
}
