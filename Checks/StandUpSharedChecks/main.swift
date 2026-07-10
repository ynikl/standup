import Foundation

struct SharedCheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SharedCheckFailure(message: message)
    }
}

@main
@MainActor
struct StandUpSharedChecks {
    static func main() throws {
        try checkRestoresPersistedSession()
        print("PASS restores persisted session")
        try checkPersistsSessionAfterActivity()
        print("PASS persists session after activity")
        print("\nAll 2 shared checks passed")
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

@MainActor
private struct NoopNotifier: StandUpNotificationScheduling {
    func requestAuthorization() async throws -> Bool { true }
    func scheduleSedentaryReminder(reason: NotificationReason?, seatedMinutes: Int?) async {}
    func scheduleSedentaryReminder(at date: Date, reason: NotificationReason?) async {}
    func cancelSedentaryReminders() async {}
}

@MainActor
private final class MemorySync: StandUpSyncing {
    var onReceive: ((StandUpDataState) -> Void)?
    var published: [StandUpDataState] = []

    func activate() {}

    func publish(_ state: StandUpDataState) {
        published.append(state)
    }
}
