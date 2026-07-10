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

- [ ] **Step 1: Register recovery checks**

Add five checks before the existing activation-failure check and update the final count from 14 to 19:

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
```

- [ ] **Step 2: Add recover-on-second-attempt adapters and checks**

Use dedicated test adapters with counters:

- `RecoveringLoadStorage` throws from its first `load()`, then returns a non-default persisted state and records any save attempts.
- `RecoveringSaveStorage` loads successfully, throws from its first `save(_:)`, then stores the second value.
- `RecoveringSync` throws from its first `publish(_:)`, then records the second state.
- `RecoveringNotifier` throws from its first `replaceSedentaryReminders(with:)`, then records the second plan.
- `BlockingRetryNotifier` fails the initial replacement, suspends the retry replacement until released, and exposes a retry-start waiter.

The checks must assert:

```swift
try expect(model.settings.sedentaryThresholdMinutes == 75, "load retry should restore settings")
try expect(storage.saveCount == 0, "load retry must not overwrite unreadable data")
try expect(model.operationalError == nil, "load retry should clear the error")

try expect(storage.saveAttempts == 2, "save retry should make one new attempt")
try expect(model.operationalError == nil, "save retry should clear the error")

try expect(sync.publishAttempts == 2, "sync retry should make one new attempt")
try expect(storage.saveCount == 1, "sync retry must not rewrite local storage")
try expect(model.operationalError == nil, "sync retry should clear the error")

try expect(notifier.replaceAttempts == 2, "reminder retry should make one new attempt")
try expect(model.operationalError == nil, "reminder retry should clear the error")

try expect(model.isRetryingOperationalWork, "model should expose retry progress")
try expect(notifier.replaceAttempts == 2, "concurrent retry must not duplicate work")
try expect(!model.isRetryingOperationalWork, "retry progress should reset")
```

- [ ] **Step 3: Run the shared checks and verify red**

Run:

```sh
Checks/run-shared-checks.sh
```

Expected: compilation fails because `retryOperationalWork` and `isRetryingOperationalWork` do not exist.

### Task 2: Implement Layered Operational Recovery

**Files:**
- Modify: `Apps/Shared/StandUpAppModel.swift:9-318`
- Test: `Checks/StandUpSharedChecks/main.swift`

- [ ] **Step 1: Distinguish load and save failures**

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

- [ ] **Step 2: Publish retry progress and command**

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
        }
    }

    guard persistenceFailure == nil else {
        return
    }

    if syncError != nil {
        publishSynchronizedState()
    }

    if notificationError != nil || restoredStorage {
        lastReminderPlan = nil
        reconcileReminders(now: now)
        await reminderReconciliationTask?.value
    }

    refreshOperationalError()
}
```

- [ ] **Step 3: Add storage reload and direct publish helpers**

`retryStorageLoad(now:)` calls `storage.load()`. On success it enables persistence, clears the persistence failure, restores settings and revision, sorts records, reconstructs `SedentaryEngine` with the persisted session and supplied date, updates the snapshot, refreshes the visible error, and returns `true`. On failure it retains a `.load(...)` failure, disables persistence, refreshes the error, and returns `false`.

Extract the current `sync.publish` block into:

```swift
private func publishSynchronizedState() {
    do {
        try sync.publish(synchronizedState)
        syncError = nil
    } catch {
        syncError = "Unable to sync data: \(error.localizedDescription)"
    }
    refreshOperationalError()
}
```

Call this helper from normal synchronized persistence and explicit retry.

- [ ] **Step 4: Run shared checks and verify green**

Run:

```sh
Checks/run-shared-checks.sh
```

Expected: all 19 shared checks pass.

### Task 3: Add Failing Cross-Platform UI Contract

**Files:**
- Create: `Checks/check-operational-recovery-ui.sh`
- Test: `Apps/iOS/SettingsView.swift`
- Test: `Apps/Watch/WatchRootView.swift`
- Test: `Apps/Shared/StandUpAppModel.swift`

- [ ] **Step 1: Create the source contract check**

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

- [ ] **Step 2: Run the UI check and verify red**

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

- [ ] **Step 1: Add the iPhone App status section**

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

- [ ] **Step 2: Add a stable Watch retry control**

Replace the standalone phase image with a 44-point header row containing an invisible leading placeholder, the centered phase image, and `WatchOperationalRetryButton` on the trailing edge. The private button view reads `operationalError` and `isRetryingOperationalWork`, renders a warning icon or progress indicator in a fixed 44 by 44 frame, invokes `retryOperationalWork()`, disables during retry, and applies:

```swift
.accessibilityLabel("Retry failed operation")
.accessibilityHint(error)
```

When there is no error, it renders an accessibility-hidden clear 44-point placeholder so the phase icon never shifts.

- [ ] **Step 3: Run the focused UI and shared checks**

Run:

```sh
Checks/check-operational-recovery-ui.sh
Checks/run-shared-checks.sh
```

Expected: UI check exits 0 and all 19 shared checks pass.

- [ ] **Step 4: Add the check to verification documentation**

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

- [ ] **Step 1: Run all repository checks**

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

Expected: 24 core checks and 19 shared checks pass, every source check exits 0, and the package build exits 0.

- [ ] **Step 2: Build both application targets**

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

- [ ] **Step 3: Request independent code review**

Review the implementation against `docs/superpowers/specs/2026-07-10-operational-error-recovery-design.md`. Resolve all Critical and Important findings, then rerun affected checks.

- [ ] **Step 4: Commit the verified change**

```sh
git add Apps/Shared/StandUpAppModel.swift Apps/iOS/SettingsView.swift Apps/Watch/WatchRootView.swift Checks/StandUpSharedChecks/main.swift Checks/check-operational-recovery-ui.sh README.md docs/DEVELOPMENT.md docs/superpowers/plans/2026-07-10-operational-error-recovery.md
git commit -m "feat: add operational recovery controls"
```
