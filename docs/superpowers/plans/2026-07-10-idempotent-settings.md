# Idempotent Settings Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make unchanged threshold and active-window assignments side-effect free at the shared app-model boundary.

**Architecture:** Construct a normalized candidate `StandUpSettings` value in each update method and return when it equals the current value. Preserve the existing state revision, engine update, snapshot, persistence, synchronization, and reminder path for genuine changes.

**Tech Stack:** Swift 6, Combine observation, existing executable shared-model checks

---

### Task 1: Add A Failing Settings Idempotency Check

**Files:**
- Modify: `Checks/StandUpSharedChecks/main.swift:31`
- Test: `Checks/StandUpSharedChecks/main.swift`

- [ ] **Step 1: Register the new shared check**

Add this call after `checkPersistsOnlyStateChangingTicks()`:

```swift
try checkPersistsOnlyChangedSettings()
print("PASS persists only changed settings")
```

Update the final summary to:

```swift
print("\nAll 13 shared checks passed")
```

- [ ] **Step 2: Add the check implementation**

```swift
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
```

- [ ] **Step 3: Run the shared checks and verify red**

Run: `Checks/run-shared-checks.sh`

Expected: exit 1 with `normalized unchanged settings should not persist` because the current app model saves both unchanged assignments.

### Task 2: Guard Normalized No-Op Settings

**Files:**
- Modify: `Apps/Shared/StandUpAppModel.swift:119`
- Test: `Checks/StandUpSharedChecks/main.swift`

- [ ] **Step 1: Guard updateThreshold**

Replace `updateThreshold` with:

```swift
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
```

- [ ] **Step 2: Guard updateActiveWindow**

Replace `updateActiveWindow` with:

```swift
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
```

- [ ] **Step 3: Run the focused checks and verify green**

Run: `Checks/run-shared-checks.sh`

Expected: all 13 shared checks pass.

### Task 3: Verify And Commit

**Files:**
- Verify: `Apps/Shared/StandUpAppModel.swift`
- Verify: `Checks/StandUpSharedChecks/main.swift`

- [ ] **Step 1: Run the complete repository matrix**

Run each command independently:

```sh
swift run StandUpCoreChecks
Checks/run-shared-checks.sh
Checks/check-watch-timeline.sh
Checks/check-watch-bundle-metadata.sh
Checks/check-watch-startup-order.sh
swift build
```

Expected: 24 core checks and 13 shared checks pass, all Watch checks exit 0, and the package build exits 0.

- [ ] **Step 2: Build the Watch target**

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
git add Apps/Shared/StandUpAppModel.swift Checks/StandUpSharedChecks/main.swift docs/superpowers/plans/2026-07-10-idempotent-settings.md
git commit -m "fix: ignore unchanged settings updates"
```
