# Reliable Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sedentary sessions restorable, reminder schedules deterministic, and phone/watch state merges convergent.

**Architecture:** `StandUpCore` owns serializable session state, reminder planning, and revision-based state merging. `Apps/Shared` persists local engine state, sends only synchronized data through WatchConnectivity, and replaces pending local notifications from the core plan.

**Tech Stack:** Swift 6, Foundation, Swift Package Manager, UserNotifications, WatchConnectivity

---

### Task 1: Restorable Session And Tick-Based Activity Clear

**Files:**
- Modify: `Sources/StandUpCore/SedentaryEngine.swift`
- Modify: `Checks/StandUpCoreChecks/main.swift`

- [ ] **Step 1: Write failing activity-tick and restoration checks**

Add the following check registrations and functions to `Checks/StandUpCoreChecks/main.swift`:

```swift
("tick clears continuous active movement", checkTickActivityClear),
("sedentary movement interrupts active clear", checkInterruptedActivityClear),
("session state survives encoding and restoration", checkSessionRestoration),

func checkTickActivityClear() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)
    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.tick, at: start.adding(minutes: 45))
    _ = engine.ingest(.activity(.active), at: start.adding(minutes: 50))

    let output = engine.ingest(.tick, at: start.adding(minutes: 52))
    try expect(output.endedRecords.first?.endReason == .stoodUp, "tick should finish active session")
}

func checkInterruptedActivityClear() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)
    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.tick, at: start.adding(minutes: 45))
    _ = engine.ingest(.activity(.active), at: start.adding(minutes: 50))
    _ = engine.ingest(.activity(.sedentary), at: start.adding(minutes: 51))

    let output = engine.ingest(.tick, at: start.adding(minutes: 52))
    try expect(output.endedRecords.isEmpty, "sedentary signal should cancel active candidate")
}

func checkSessionRestoration() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)
    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.tick, at: start.adding(minutes: 45))
    _ = engine.ingest(.ignore(.thirtyMinutes), at: start.adding(minutes: 46))

    let data = try JSONEncoder().encode(engine.sessionState)
    let state = try JSONDecoder().decode(SedentarySessionState.self, from: data)
    let restored = SedentaryEngine(settings: .default, calendar: .standUpCheck, sessionState: state)

    try expect(restored.snapshot(at: start.adding(minutes: 50)).phase == .ignored(until: start.adding(minutes: 76)), "restored ignore window")
    try expect(restored.snapshot(at: start.adding(minutes: 50)).seatedMinutes == 50, "restored seated duration")
}
```

- [ ] **Step 2: Run checks and verify red**

Run: `swift run StandUpCoreChecks`

Expected: compilation fails because `sessionState`, `SedentarySessionState`, and the restoring initializer do not exist; after those signatures exist, the tick check must fail until tick-based activity clearing is implemented.

- [ ] **Step 3: Implement serializable state and shared activity evaluation**

Add this public value and store it in the engine instead of separate private session fields:

```swift
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

    public init(
        seatedSince: Date? = nil,
        thresholdReachedAt: Date? = nil,
        activeCandidateSince: Date? = nil,
        lastReminderAt: Date? = nil,
        ignoreUntil: Date? = nil,
        ignoreEvents: [IgnoreEvent] = [],
        pauseReason: PauseReason? = nil,
        latestActivity: ActivitySignal? = nil
    ) {
        self.seatedSince = seatedSince
        self.thresholdReachedAt = thresholdReachedAt
        self.activeCandidateSince = activeCandidateSince
        self.lastReminderAt = lastReminderAt
        self.ignoreUntil = ignoreUntil
        self.ignoreEvents = ignoreEvents
        self.pauseReason = pauseReason
        self.latestActivity = latestActivity
    }
}
```

Expose `public private(set) var sessionState` and add:

```swift
public init(
    settings: StandUpSettings,
    calendar: Calendar = .current,
    sessionState: SedentarySessionState = .empty
)
```

Set `latestActivity` on activity ingestion. Route both `.tick` and `.activity(.active)` through `evaluateActiveClear(at:)`, which returns `.empty` unless the latest activity is active and the candidate is at least `activeClearMinutes` old; otherwise it calls `finishSession(at:reason:)`. Clear the candidate when sedentary activity resumes and assign `.empty` in `clearSession()`.

- [ ] **Step 4: Run checks and verify green**

Run: `swift run StandUpCoreChecks`

Expected: all existing checks plus the three new checks pass.

- [ ] **Step 5: Commit the increment**

```bash
git add Sources/StandUpCore/SedentaryEngine.swift Checks/StandUpCoreChecks/main.swift
git commit -m "fix: restore active sedentary sessions"
```

### Task 2: Core Reminder Plan

**Files:**
- Create: `Sources/StandUpCore/ReminderPlan.swift`
- Modify: `Sources/StandUpCore/Settings.swift`
- Modify: `Sources/StandUpCore/SedentaryEngine.swift`
- Modify: `Checks/StandUpCoreChecks/main.swift`

- [ ] **Step 1: Write failing reminder-plan checks**

Add registrations and checks for these exact outcomes:

```swift
("pre-threshold ignore never reminds early", checkPreThresholdIgnorePlan),
("reminder plan stops at active-window end", checkReminderActiveWindowBoundary),
("reminder plan repeats and caps pending requests", checkReminderPlanCadence),

func checkPreThresholdIgnorePlan() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)
    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.ignore(.fifteenMinutes), at: start.adding(minutes: 5))

    let plan = engine.reminderPlan(at: start.adding(minutes: 5))
    try expect(plan.reminders.first?.deliveryDate == start.adding(minutes: 45), "ignore ending before threshold must not remind early")
    try expect(plan.reminders.first?.reason == .thresholdReached, "first planned reminder reason")
}

func checkReminderActiveWindowBoundary() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 21, minute: 30)
    _ = engine.ingest(.activity(.sedentary), at: start)

    let plan = engine.reminderPlan(at: start)
    try expect(plan.reminders.isEmpty, "22:15 threshold is outside active hours")
}

func checkReminderPlanCadence() throws {
    let settings = StandUpSettings(sedentaryThresholdMinutes: 15, activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60))
    var engine = SedentaryEngine(settings: settings, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 0, minute: 0)
    _ = engine.ingest(.activity(.sedentary), at: start)

    let plan = engine.reminderPlan(at: start, limit: 60)
    try expect(plan.reminders.count == 60, "plan should respect pending-request cap")
    try expect(plan.reminders[0].deliveryDate == start.adding(minutes: 15), "threshold delivery")
    try expect(plan.reminders[1].deliveryDate == start.adding(minutes: 25), "repeat cadence")
}
```

- [ ] **Step 2: Run checks and verify red**

Run: `swift run StandUpCoreChecks`

Expected: compilation fails because `ReminderPlan`, `reminderPlan(at:limit:)`, and active-window end calculation do not exist.

- [ ] **Step 3: Implement reminder values and planning rules**

Create these public values in `ReminderPlan.swift`:

```swift
public struct PlannedReminder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var deliveryDate: Date
    public var reason: NotificationReason
}

public struct ReminderPlan: Codable, Equatable, Sendable {
    public var reminders: [PlannedReminder]
    public static let empty = ReminderPlan(reminders: [])
}
```

Add `ActiveWindow.end(containing:calendar:) -> Date?`. Add `SedentaryEngine.reminderPlan(at:limit:)` with a default limit of 60. Start at `max(thresholdDate, unexpiredIgnoreUntil)`, select `.thresholdReached` for the first reminder when the engine has not crossed the threshold, append repeat reminders at the configured cadence, and stop before the active-window end or limit.

- [ ] **Step 4: Run checks and verify green**

Run: `swift run StandUpCoreChecks`

Expected: all checks pass, including early-ignore, boundary, cadence, and cap cases.

- [ ] **Step 5: Commit the increment**

```bash
git add Sources/StandUpCore/ReminderPlan.swift Sources/StandUpCore/Settings.swift Sources/StandUpCore/SedentaryEngine.swift Checks/StandUpCoreChecks/main.swift
git commit -m "feat: plan sedentary reminders in core"
```

### Task 3: Revision-Based Synchronized State

**Files:**
- Create: `Sources/StandUpCore/StandUpDataState.swift`
- Modify: `Sources/StandUpCore/SedentaryRecord.swift`
- Modify: `Checks/StandUpCoreChecks/main.swift`

- [ ] **Step 1: Write failing merge and migration checks**

Add these registrations and checks:

```swift
("newer synchronized revisions win", checkSynchronizedMerge),
("legacy records default modification time", checkLegacyRecordRevision),

func checkSynchronizedMerge() throws {
    let start = Date.standUpCheck(hour: 9, minute: 0)
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    let localRecord = SedentaryRecord(
        id: id,
        sedentaryStartedAt: start,
        thresholdReachedAt: start.adding(minutes: 45),
        endedAt: start.adding(minutes: 60),
        endReason: .stoodUp,
        ignoreEvents: [],
        modifiedAt: start.adding(minutes: 60)
    )
    var remoteRecord = localRecord
    remoteRecord.correction = .excluded(reason: .meeting)
    remoteRecord.modifiedAt = start.adding(minutes: 70)

    let local = StandUpDataState(settings: .default, settingsUpdatedAt: start, records: [localRecord])
    let remoteSettings = StandUpSettings(sedentaryThresholdMinutes: 60)
    let remote = StandUpDataState(settings: remoteSettings, settingsUpdatedAt: start.adding(minutes: 1), records: [remoteRecord])
    let merged = local.merging(remote)

    try expect(merged.settings == remoteSettings, "newer settings should win")
    try expect(merged.records.first?.correction == .excluded(reason: .meeting), "newer correction should win")
    try expect(remote.merging(local).settings == remoteSettings, "stale settings should be ignored")
}

func checkLegacyRecordRevision() throws {
    let start = Date.standUpCheck(hour: 9, minute: 0)
    let record = SedentaryRecord(
        sedentaryStartedAt: start,
        thresholdReachedAt: start.adding(minutes: 45),
        endedAt: start.adding(minutes: 60),
        endReason: .stoodUp,
        ignoreEvents: []
    )
    let encoded = try JSONEncoder().encode(record)
    var object = try require(JSONSerialization.jsonObject(with: encoded) as? [String: Any], "record JSON object")
    object.removeValue(forKey: "modifiedAt")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(SedentaryRecord.self, from: legacy)

    try expect(decoded.modifiedAt == decoded.endedAt, "legacy record should use end time as revision")
}
```

- [ ] **Step 2: Run checks and verify red**

Run: `swift run StandUpCoreChecks`

Expected: compilation fails because `StandUpDataState`, `modifiedAt`, and `merging(_:)` do not exist.

- [ ] **Step 3: Implement revision metadata and deterministic merge**

Add `modifiedAt: Date` to `SedentaryRecord`, defaulting to `endedAt` in the initializer. Implement custom `Codable` decoding with `decodeIfPresent(Date.self, forKey: .modifiedAt) ?? endedAt` so current JSON remains readable.

Create:

```swift
public struct StandUpDataState: Codable, Equatable, Sendable {
    public var settings: StandUpSettings
    public var settingsUpdatedAt: Date
    public var records: [SedentaryRecord]

    public func merging(_ incoming: StandUpDataState) -> StandUpDataState
}
```

Choose settings from the greater revision. Merge records by UUID and replace only when the incoming `modifiedAt` is later. Sort merged records by `thresholdReachedAt` descending.

- [ ] **Step 4: Run checks and verify green**

Run: `swift run StandUpCoreChecks`

Expected: migration and all merge checks pass.

- [ ] **Step 5: Commit the increment**

```bash
git add Sources/StandUpCore/StandUpDataState.swift Sources/StandUpCore/SedentaryRecord.swift Checks/StandUpCoreChecks/main.swift
git commit -m "fix: converge synchronized standup state"
```

### Task 4: Local Persistence And Sync Separation

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/StandUpCore/StandUpDataState.swift`
- Modify: `Checks/StandUpCoreChecks/main.swift`
- Modify: `Apps/Shared/StandUpStorage.swift`
- Modify: `Apps/Shared/WatchConnectivityBridge.swift`
- Modify: `Apps/Shared/StandUpAppModel.swift`
- Create: `Tests/StandUpSharedTests/StandUpAppModelTests.swift`

- [ ] **Step 1: Add a package-level round-trip check for the persisted payload shape**

Define `StandUpLocalState` in `StandUpCore/StandUpDataState.swift` so it is testable by the existing check runner:

```swift
public struct StandUpLocalState: Codable, Equatable, Sendable {
    public var synchronized: StandUpDataState
    public var session: SedentarySessionState

    public init(synchronized: StandUpDataState, session: SedentarySessionState = .empty) {
        self.synchronized = synchronized
        self.session = session
    }
}
```

Add `StandUpShared` and `StandUpSharedTests` targets in `Package.swift`. The shared target includes `NotificationScheduling.swift`, `StandUpAppModel.swift`, `StandUpStorage.swift`, and `WatchConnectivityBridge.swift`, and depends on `StandUpCore`.

Add this legacy check to `StandUpCoreChecks`:

```swift
("legacy local state decodes without a session", checkLegacyLocalState),

func checkLegacyLocalState() throws {
    let json = """
    {
      "settings": {
        "sedentaryThresholdMinutes": 45,
        "activeClearMinutes": 2,
        "repeatReminderMinutes": 10,
        "activeWindow": { "startMinuteOfDay": 540, "endMinuteOfDay": 1320 }
      },
      "records": []
    }
    """
    let state = try JSONDecoder().decode(StandUpLocalState.self, from: Data(json.utf8))
    try expect(state.session == .empty, "legacy state should start with an empty session")
    try expect(state.synchronized.settingsUpdatedAt == Date(timeIntervalSince1970: 0), "legacy settings revision")
}
```

Create `StandUpAppModelTests.swift` with the following test structure; the adapter fakes implement the protocol methods in force at this task:

```swift
import StandUpCore
@testable import StandUpShared
import XCTest

@MainActor
final class StandUpAppModelTests: XCTestCase {
    func testRestoresPersistedSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60))
        var engine = SedentaryEngine(settings: settings)
        _ = engine.ingest(.activity(.sedentary), at: now.addingTimeInterval(-10 * 60))
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let storage = MemoryStorage(state: StandUpLocalState(synchronized: synchronized, session: engine.sessionState))

        let model = StandUpAppModel(storage: storage, notifier: NoopNotifier(), sync: MemorySync(), now: now)

        XCTAssertEqual(model.snapshot.seatedMinutes, 10)
    }

    func testPersistsSessionAfterActivity() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = StandUpSettings(activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60))
        let synchronized = StandUpDataState(settings: settings, settingsUpdatedAt: now, records: [])
        let storage = MemoryStorage(state: StandUpLocalState(synchronized: synchronized, session: .empty))
        let model = StandUpAppModel(storage: storage, notifier: NoopNotifier(), sync: MemorySync(), now: now)

        model.ingest(activity: .sedentary, now: now)

        XCTAssertEqual(storage.state.session.seatedSince, now)
    }
}

private final class MemoryStorage: StandUpStorage {
    var state: StandUpLocalState

    init(state: StandUpLocalState) {
        self.state = state
    }

    func load() throws -> StandUpLocalState { state }
    func save(_ state: StandUpLocalState) throws { self.state = state }
}

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
    func publish(_ state: StandUpDataState) { published.append(state) }
}
```

- [ ] **Step 2: Run checks and verify red**

Run: `swift run StandUpCoreChecks`

Expected: compilation fails until `StandUpLocalState` and legacy decoding are implemented.

- [ ] **Step 3: Implement local storage and synchronization payload separation**

Change `StandUpStorage` to load/save `StandUpLocalState`. Change `StandUpSyncing` and `WatchConnectivityStandUpBridge` to publish and receive `StandUpDataState` only. Replace actor-isolated default adapter arguments with optional nil defaults and instantiate concrete adapters inside the `@MainActor` initializer body.

In `StandUpAppModel`:

- initialize the engine with the locally restored session;
- keep `settingsUpdatedAt` in model state;
- persist `engine.sessionState` after every engine event;
- publish only after settings or records change;
- set record `modifiedAt` when correcting or restoring;
- merge incoming state with `StandUpDataState.merging(_:)`;
- never replace the local engine session from WatchConnectivity.

- [ ] **Step 4: Run core verification**

Run: `swift test && swift run StandUpCoreChecks && swift build`

Expected: all checks pass and the Swift package builds without warnings or errors.

- [ ] **Step 5: Commit the increment**

```bash
git add Package.swift Sources/StandUpCore/StandUpDataState.swift Apps/Shared/StandUpStorage.swift Apps/Shared/WatchConnectivityBridge.swift Apps/Shared/StandUpAppModel.swift Tests/StandUpSharedTests/StandUpAppModelTests.swift Checks/StandUpCoreChecks/main.swift
git commit -m "feat: persist monitoring sessions locally"
```

### Task 5: Execute Reminder Plans And Surface Adapter Failures

**Files:**
- Modify: `Apps/Shared/NotificationScheduling.swift`
- Modify: `Apps/Shared/StandUpAppModel.swift`
- Create: `Tests/StandUpSharedTests/NotificationSchedulingTests.swift`
- Modify: `README.md`
- Modify: `docs/DEVELOPMENT.md`

- [ ] **Step 1: Make scheduler failure behavior explicit at the protocol boundary**

Replace the two single-reminder protocol methods with:

```swift
func replaceSedentaryReminders(with plan: ReminderPlan) async throws
func cancelSedentaryReminders() async
```

Add `@Published private(set) var operationalError: String?` to `StandUpAppModel`. Calls to replace the plan catch errors and set a concise diagnostic string; successful replacement clears the notification error.

Update `NoopNotifier` in `StandUpAppModelTests.swift` to implement the new protocol:

```swift
private struct NoopNotifier: StandUpNotificationScheduling {
    func requestAuthorization() async throws -> Bool { true }
    func replaceSedentaryReminders(with plan: ReminderPlan) async throws {}
    func cancelSedentaryReminders() async {}
}
```

Before changing production code, add this test in `NotificationSchedulingTests.swift` and run `swift test`; compilation must fail because `requests(for:now:)` does not exist:

```swift
import StandUpCore
@testable import StandUpShared
import UserNotifications
import XCTest

final class NotificationSchedulingTests: XCTestCase {
    func testBuildsStableRequestsFromPlan() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = ReminderPlan(reminders: [
            PlannedReminder(id: "threshold-1", deliveryDate: now.addingTimeInterval(60), reason: .thresholdReached),
            PlannedReminder(id: "repeat-1", deliveryDate: now.addingTimeInterval(120), reason: .repeatReminder)
        ])

        let requests = LocalStandUpNotificationScheduler().requests(for: plan, now: now)

        XCTAssertEqual(requests.map(\.identifier), ["sedentary-reminder-threshold-1", "sedentary-reminder-repeat-1"])
        let intervals = try requests.map { request in
            try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger).timeInterval
        }
        XCTAssertEqual(intervals, [60, 120])
    }
}
```

- [ ] **Step 2: Implement complete notification-plan replacement**

Use stable `PlannedReminder.id` values for `UNNotificationRequest` identifiers. Before adding the plan, query pending requests, remove every identifier with the `sedentary-reminder` prefix, then add each future reminder with `UNTimeIntervalNotificationTrigger`. Do not use `try?` when adding requests.

Replace `scheduleNextReminderIfNeeded` with a single reconciliation method:

```swift
private func reconcileReminders(now: Date) {
    let plan = engine.reminderPlan(at: now)
    Task {
        do {
            try await notifier.replaceSedentaryReminders(with: plan)
            operationalError = nil
        } catch {
            operationalError = "Unable to update reminders: \(error.localizedDescription)"
        }
    }
}
```

Invoke reconciliation after activity, ignore, settings changes, restoration, and ticks that change the engine output. Remove `scheduledReminderAt` and all app-layer threshold arithmetic.

- [ ] **Step 3: Update documentation to match verified behavior and limits**

Add README bullets stating "In-progress sessions are restored after a local app restart" and "A bounded reminder series is scheduled only within active hours." Add a development note stating that watchOS background motion delivery still requires real-device validation. Keep the existing disclaimer that second-level precision is not promised.

- [ ] **Step 4: Run final verification and inspect changes**

Run:

```bash
swift run StandUpCoreChecks
swift build
git diff --check
git status --short
```

Expected: all checks pass, package build succeeds, diff check is clean, and only intended files plus the pre-existing untracked `StandUp.xcodeproj/` appear.

- [ ] **Step 5: Commit the increment**

```bash
git add Apps/Shared/NotificationScheduling.swift Apps/Shared/StandUpAppModel.swift Tests/StandUpSharedTests/NotificationSchedulingTests.swift README.md docs/DEVELOPMENT.md
git commit -m "fix: reconcile bounded reminder schedules"
```
