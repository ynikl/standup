# State-Change Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent unchanged foreground timer ticks from rewriting local state while preserving writes for monitoring-state transitions.

**Architecture:** Compare `SedentarySessionState` immediately before and after each engine event in `StandUpAppModel`. Pass the comparison result into the existing `apply` method, which remains responsible for snapshot publication, persistence, synchronization, and reminder reconciliation.

**Tech Stack:** Swift 6, Foundation, existing executable shared-model checks

---

### Task 1: Add A Failing Persistence Check

**Files:**
- Modify: `Checks/StandUpSharedChecks/main.swift:13`
- Test: `Checks/StandUpSharedChecks/main.swift`

- [ ] **Step 1: Register the new shared check**

Add this call after `checkPersistsSessionAfterActivity()`:

```swift
try checkPersistsOnlyStateChangingTicks()
print("PASS persists only state-changing ticks")
```

- [ ] **Step 2: Add the check implementation**

```swift
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
```

- [ ] **Step 3: Count saves in the memory storage test double**

```swift
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
```

- [ ] **Step 4: Run the shared checks and verify red**

Run: `Checks/run-shared-checks.sh`

Expected: exit 1 with `unchanged tick should not persist` because the save count is 2 after the one-minute tick.

### Task 2: Persist Only Engine State Changes

**Files:**
- Modify: `Apps/Shared/StandUpAppModel.swift:87`
- Test: `Checks/StandUpSharedChecks/main.swift`

- [ ] **Step 1: Compare the session around each engine event**

Replace the three event methods with:

```swift
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
```

- [ ] **Step 2: Gate persistence in apply**

Change the method signature and persistence call to:

```swift
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
```

- [ ] **Step 3: Run the focused check and verify green**

Run: `Checks/run-shared-checks.sh`

Expected: all 12 shared checks pass.

### Task 3: Run The Full Verification Matrix

**Files:**
- Verify: `Apps/Shared/StandUpAppModel.swift`
- Verify: `Checks/StandUpSharedChecks/main.swift`

- [ ] **Step 1: Run all repository checks**

Run each command independently:

```sh
swift run StandUpCoreChecks
Checks/run-shared-checks.sh
Checks/check-watch-timeline.sh
Checks/check-watch-bundle-metadata.sh
swift build
```

Expected: 24 core checks pass, 12 shared checks pass, both Watch checks exit 0, and the package build exits 0.

- [ ] **Step 2: Build the Watch target**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj \
  -target StandUpWatch \
  -configuration Debug \
  -sdk watchsimulator \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit the verified change**

```sh
git add Apps/Shared/StandUpAppModel.swift Checks/StandUpSharedChecks/main.swift docs/superpowers/plans/2026-07-10-state-change-persistence.md
git commit -m "perf: skip unchanged session writes"
```
