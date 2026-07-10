# Operational Error Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make storage, synchronization, and reminder failures visible and retryable from both iPhone and Apple Watch.

**Architecture:** Keep failure ownership inside `StandUpAppModel`. Distinguish load and save failures internally, retry failed layers in storage-to-sync-to-reminder order, and publish one loading state for platform views. iPhone uses a Form section with text and a stable Retry control; Watch uses a compact 44-point warning control without changing the core engine or synchronized schema.

**Tech Stack:** Swift 6, SwiftUI, Foundation, UserNotifications, WatchConnectivity, POSIX shell checks, Swift Package Manager, Xcode simulator SDK builds

---

### Task 1: Specify Retry Behavior With Failing Shared Checks

**Files:**
- Modify: `Checks/StandUpSharedChecks/main.swift`
- Test: `Checks/run-shared-checks.sh`

- [x] **Step 1: Register recovery checks**

Add six checks before the existing activation-failure check and update the final count from 14 to 20:

```swift
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
```

- [x] **Step 2: Add recover-on-second-attempt adapters and checks**

Use dedicated test adapters with counters:

- `RecoveringLoadStorage` throws from its first `load()`, then returns a non-default persisted state and records any save attempts.
- `RecoveringSaveStorage` loads successfully, throws from its first `save(_:)`, then stores the second value.
- `RecoveringSync` throws from its first `publish(_:)`, then records the second state.
- `RecoveringNotifier` throws from its first `replaceSedentaryReminders(with:)`, then records the second plan.
- `BlockingRetryNotifier` fails the initial replacement, suspends the retry replacement until released, and exposes a retry-start waiter.
- `BlockingActivationSync` reports an activation error on startup, then suspends retry activation until released so loading and duplicate-retry behavior can be verified.

The checks must assert:

```swift
try expect(model.settings.sedentaryThresholdMinutes == 90, "load retry should preserve newer synced settings")
try expect(model.snapshot.seatedMinutes == 1, "load retry should preserve the current session")
try expect(storage.saveCount == 1, "load retry should persist after a successful read")
try expect(sync.published.last?.settings.sedentaryThresholdMinutes == 90, "load retry should publish merged settings")
try expect(model.operationalError == nil, "load retry should clear the error")

try expect(storage.saveAttempts == 2, "save retry should make one new attempt")
try expect(sync.published.last?.settings.sedentaryThresholdMinutes == 60, "save retry should publish recovered settings")
try expect(model.operationalError == nil, "save retry should clear the error")

try expect(sync.publishAttempts == 2, "sync retry should make one new attempt")
try expect(storage.saveCount == 1, "sync retry must not rewrite local storage")
try expect(model.operationalError == nil, "sync retry should clear the error")

try expect(notifier.replaceAttempts == 2, "reminder retry should make one new attempt")
try expect(model.operationalError == nil, "reminder retry should clear the error")

try expect(model.isRetryingOperationalWork, "model should expose retry progress")
try expect(notifier.replaceAttempts == 2, "concurrent retry must not duplicate work")
try expect(!model.isRetryingOperationalWork, "retry progress should reset")

try expect(sync.activationAttempts == 2, "sync retry should reactivate once")
try expect(model.isRetryingOperationalWork, "activation retry should keep progress visible until completion")
try expect(model.operationalError == nil, "successful activation retry should clear the error")
```

- [x] **Step 3: Run the shared checks and verify red**

Run:

```sh
Checks/run-shared-checks.sh
```

Expected: compilation fails because `retryOperationalWork` and `isRetryingOperationalWork` do not exist.

### Task 2: Implement Layered Operational Recovery

**Files:**
- Modify: `Apps/Shared/StandUpAppModel.swift:9-318`
- Test: `Checks/StandUpSharedChecks/main.swift`

- [x] **Step 1: Distinguish load and save failures**

Add a private failure type:

```swift
private enum PersistenceFailure {
    case load(String)
    case save(String)

    var message: String {
        switch self {
        case .load(let message), .save(let message):
            return message
        }
    }
}
```

Replace `persistenceError: String?` with `persistenceFailure: PersistenceFailure?`. Initialization uses `.load(...)`; save failures use `.save(...)`; successful save clears the failure; `refreshOperationalError()` reads `persistenceFailure?.message`.

- [x] **Step 2: Publish retry progress and command**

Add:

```swift
@Published private(set) var isRetryingOperationalWork = false
```

Implement:

```swift
func retryOperationalWork(now: Date = Date()) async {
    guard operationalError != nil, !isRetryingOperationalWork else {
        return
    }

    isRetryingOperationalWork = true
    defer { isRetryingOperationalWork = false }

    var restoredStorage = false
    if let persistenceFailure {
        switch persistenceFailure {
        case .load:
            restoredStorage = retryStorageLoad(now: now)
        case .save:
            persist(recoverStorage: true)
            restoredStorage = self.persistenceFailure == nil
        }
    }

    guard persistenceFailure == nil else {
        return
    }

    if syncPublishError != nil || restoredStorage {
        publishSynchronizedState()
    }

    if syncReceiveError != nil {
        await sync.retryActivation()
    }

    if notificationError != nil || restoredStorage {
        lastReminderPlan = nil
        reconcileReminders(now: now)
        await reminderReconciliationTask?.value
    }

    refreshOperationalError()
}
```

- [x] **Step 3: Add storage reload and direct publish helpers**

`retryStorageLoad(now:)` calls `storage.load()`. On success it merges the recovered synchronized state with the current state through `StandUpDataState.merging(_:)`. It uses the current engine session when the session changed while storage was unavailable, otherwise the recovered session. It reconstructs the engine, updates the snapshot, and persists only after the read succeeded. On failure it retains a `.load(...)` failure, disables persistence, refreshes the error, and returns `false`. A successful reload also triggers direct synchronization publishing from `retryOperationalWork`.

Extract the current `sync.publish` block into:

```swift
private func publishSynchronizedState() {
    do {
        try sync.publish(synchronizedState)
        syncPublishError = nil
    } catch {
        syncPublishError = "Unable to sync data: \(error.localizedDescription)"
    }
    refreshOperationalError()
}
```

Call this helper from normal synchronized persistence and explicit retry.

Split publish and receive/activation failures so an incoming state cannot clear a pending publish failure. Add an activation-success callback and async `retryActivation()` to `StandUpSyncing`; the retry remains in progress until WatchConnectivity reports completion, and a successful retry clears only the receive/activation failure. `WatchConnectivityStandUpBridge` replays the latest received application context after activation, including when the session was already active, so a corrected payload can recover a prior decode failure.

- [x] **Step 4: Run shared checks and verify green**

Run:

```sh
Checks/run-shared-checks.sh
```

Expected: all 20 shared checks pass.

### Task 3: Add Failing Cross-Platform UI Contract

**Files:**
- Create: `Checks/check-operational-recovery-ui.sh`
- Test: `Apps/iOS/SettingsView.swift`
- Test: `Apps/Watch/WatchRootView.swift`
- Test: `Apps/Shared/StandUpAppModel.swift`

- [x] **Step 1: Create the source contract check**

```sh
#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
MODEL="$ROOT/Apps/Shared/StandUpAppModel.swift"
SETTINGS="$ROOT/Apps/iOS/SettingsView.swift"
WATCH="$ROOT/Apps/Watch/WatchRootView.swift"

for required in \
    '@Published private(set) var isRetryingOperationalWork' \
    'func retryOperationalWork(now: Date = Date()) async'
do
    if ! rg --quiet --fixed-strings "$required" "$MODEL"; then
        echo "Operational recovery model is missing: $required" >&2
        exit 1
    fi
done

for required in \
    'Section("App status")' \
    'model.operationalError' \
    'model.retryOperationalWork()' \
    'ProgressView()' \
    '.disabled(model.isRetryingOperationalWork)' \
    '.frame(minHeight: 44)'
do
    if ! rg --quiet --fixed-strings "$required" "$SETTINGS"; then
        echo "iPhone recovery UI is missing: $required" >&2
        exit 1
    fi
done

for required in \
    'WatchOperationalRetryButton' \
    '.frame(width: 44, height: 44)' \
    '.accessibilityLabel("Retry failed operation")' \
    '.accessibilityHint(error)'
do
    if ! rg --quiet --fixed-strings "$required" "$WATCH"; then
        echo "Watch recovery UI is missing: $required" >&2
        exit 1
    fi
done
```

- [x] **Step 2: Run the UI check and verify red**

Run:

```sh
sh Checks/check-operational-recovery-ui.sh
```

Expected: exit 1 with `Operational recovery model is missing` before Task 2, or `iPhone recovery UI is missing` after Task 2.

### Task 4: Add Accessible Recovery Controls

**Files:**
- Modify: `Apps/iOS/SettingsView.swift:9-70`
- Modify: `Apps/Watch/WatchRootView.swift:22-97`
- Modify: `README.md:27-36`
- Modify: `docs/DEVELOPMENT.md:9-41`
- Test: `Checks/check-operational-recovery-ui.sh`

- [x] **Step 1: Add the iPhone App status section**

Insert this section before `Sedentary threshold`:

```swift
if let error = model.operationalError {
    Section("App status") {
        Label {
            Text(error)
                .font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.standAlert)
        }

        Button {
            Task {
                await model.retryOperationalWork()
            }
        } label: {
            HStack(spacing: 8) {
                if model.isRetryingOperationalWork {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.isRetryingOperationalWork ? "Retrying..." : "Try again")
                Spacer()
            }
            .frame(minHeight: 44)
        }
        .disabled(model.isRetryingOperationalWork)
    }
}
```

Observe `model.settings` and copy recovered values into the three local Stepper states. This prevents controls initialized from fallback settings from writing stale values back after a successful load retry.

- [x] **Step 2: Add a stable Watch retry control**

Replace the standalone phase image with a 44-point header row containing an invisible leading placeholder, the centered phase image, and `WatchOperationalRetryButton` on the trailing edge. The private button view reads `operationalError` and `isRetryingOperationalWork`, renders a warning icon or progress indicator in a fixed 44 by 44 frame, invokes `retryOperationalWork()`, disables during retry, and applies:

```swift
.accessibilityLabel("Retry failed operation")
.accessibilityHint(error)
```

When there is no error, it renders an accessibility-hidden clear 44-point placeholder so the phase icon never shifts.

- [x] **Step 3: Run the focused UI and shared checks**

Run:

```sh
Checks/check-operational-recovery-ui.sh
Checks/run-shared-checks.sh
```

Expected: UI check exits 0 and all 20 shared checks pass.

- [x] **Step 4: Add the check to verification documentation**

Add `Checks/check-operational-recovery-ui.sh` after `Checks/check-platform-session-ownership.sh` in `README.md` and `docs/DEVELOPMENT.md`. Add this `docs/DEVELOPMENT.md` coverage bullet:

```markdown
- visible and retryable operational failures on iPhone and Watch
```

### Task 5: Verify, Review, And Commit

**Files:**
- Verify: `Apps/Shared/StandUpAppModel.swift`
- Verify: `Apps/iOS/SettingsView.swift`
- Verify: `Apps/Watch/WatchRootView.swift`
- Verify: `Checks/StandUpSharedChecks/main.swift`
- Verify: `Checks/check-operational-recovery-ui.sh`

- [x] **Step 1: Run all repository checks**

Run each command independently:

```sh
swift run StandUpCoreChecks
Checks/run-shared-checks.sh
Checks/check-watch-timeline.sh
Checks/check-watch-bundle-metadata.sh
Checks/check-watch-startup-order.sh
Checks/check-history-correction-menu.sh
Checks/check-platform-session-ownership.sh
Checks/check-operational-recovery-ui.sh
swift build
```

Expected: 24 core checks and 20 shared checks pass, every source check exits 0, and the package build exits 0.

- [x] **Step 2: Build both application targets**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj -target StandUpiOS -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Then run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj -target StandUpWatch -configuration Debug -sdk watchsimulator CODE_SIGNING_ALLOWED=NO build
```

Expected: both application targets end with `** BUILD SUCCEEDED **`.

- [x] **Step 3: Request independent code review**

Review the implementation against `docs/superpowers/specs/2026-07-10-operational-error-recovery-design.md`. Resolve all Critical and Important findings, then rerun affected checks.

- [x] **Step 4: Commit the verified change**

```sh
git add Apps/Shared/StandUpAppModel.swift Apps/iOS/SettingsView.swift Apps/Watch/WatchRootView.swift Checks/StandUpSharedChecks/main.swift Checks/check-operational-recovery-ui.sh README.md docs/DEVELOPMENT.md docs/superpowers/plans/2026-07-10-operational-error-recovery.md
git commit -m "feat: add operational recovery controls"
```
