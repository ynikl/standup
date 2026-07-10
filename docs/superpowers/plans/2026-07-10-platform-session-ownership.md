# Platform Session Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove iPhone controls and status that operate on a non-authoritative local sedentary session while preserving Watch ownership of live monitoring and skip actions.

**Architecture:** Keep the existing core engine, persistence, and synchronization payloads unchanged. Make the platform ownership decision explicit through an injected app-model capability and platform composition: iPhone disables reminder reconciliation and renders synchronized completed-record information and settings, while Watch alone starts, refreshes, displays, and controls a live session.

**Tech Stack:** Swift 6, SwiftUI, POSIX shell source-contract checks, Swift Package Manager, Xcode simulator SDK builds

---

### Task 1: Add A Failing Platform-Ownership Check

**Files:**
- Create: `Checks/check-platform-session-ownership.sh`
- Test: `Apps/iOS/DashboardView.swift`
- Test: `Apps/iOS/StandUpiOSApp.swift`
- Test: `Apps/Watch/StandUpWatchApp.swift`
- Test: `Apps/Watch/WatchRootView.swift`

- [x] **Step 1: Create the source contract check**

```sh
#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
IOS_DASHBOARD="$ROOT/Apps/iOS/DashboardView.swift"
IOS_APP="$ROOT/Apps/iOS/StandUpiOSApp.swift"
WATCH_APP="$ROOT/Apps/Watch/StandUpWatchApp.swift"
WATCH_ROOT="$ROOT/Apps/Watch/WatchRootView.swift"

for forbidden in \
    'StatusHero(' \
    'model.ignore(' \
    'IgnoreActionsView' \
    'PermissionBanner' \
    'model.refresh()'
do
    if rg --quiet --fixed-strings "$forbidden" "$IOS_DASHBOARD"; then
        echo "iPhone dashboard must not own live sessions: $forbidden" >&2
        exit 1
    fi
done

for forbidden in \
    'model.requestPermissions()' \
    'model.refresh()'
do
    if rg --quiet --fixed-strings "$forbidden" "$IOS_APP"; then
        echo "iPhone app must not start live-session services: $forbidden" >&2
        exit 1
    fi
done

for required in \
    'model.refresh()' \
    'motion.start' \
    'model.ingest(activity: signal)' \
    'await model.requestPermissions()'
do
    if ! rg --quiet --fixed-strings "$required" "$WATCH_APP"; then
        echo "Watch app is missing live-session ownership: $required" >&2
        exit 1
    fi
done

if ! rg --quiet --fixed-strings 'model.ignore(duration)' "$WATCH_ROOT"; then
    echo "Watch skip control must remain available" >&2
    exit 1
fi
```

- [x] **Step 2: Run the check and verify red**

Run:

```sh
sh Checks/check-platform-session-ownership.sh
```

Expected: exit 1 with `iPhone dashboard must not own live sessions: StatusHero(`.

### Task 2: Make Platform Ownership Honest

**Files:**
- Modify: `Apps/iOS/DashboardView.swift:7-225`
- Modify: `Apps/iOS/StandUpiOSApp.swift:7-15`
- Modify: `README.md:27-35`
- Modify: `docs/DEVELOPMENT.md:9-38`
- Test: `Checks/check-platform-session-ownership.sh`

- [x] **Step 1: Remove iPhone live-session composition**

Construct the iPhone model in review-only reminder mode and replace `StandUpiOSApp.body` with:

```swift
@StateObject private var model = StandUpAppModel(managesReminders: false)

var body: some Scene {
    WindowGroup {
        RootTabView()
            .environmentObject(model)
            .task {
                await LocalStandUpNotificationScheduler().cancelSedentaryReminders()
            }
    }
}
```

This leaves WatchConnectivity activation in `StandUpAppModel.init` intact, avoids unused iPhone notification authorization and engine ticks, and clears pending StandUp reminders left by an earlier version.

- [x] **Step 2: Reduce the iPhone dashboard to synchronized summaries**

Keep `DashboardView`, `todaySummary`, and `SummaryTile`, but make the view body:

```swift
var body: some View {
    NavigationStack {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    SummaryTile(title: "Today", value: "\(todaySummary.overdueCount)", caption: "overdue")
                    SummaryTile(title: "Overage", value: StandUpFormatting.minutes(todaySummary.totalOverageMinutes), caption: "total")
                    SummaryTile(title: "Longest", value: StandUpFormatting.minutes(todaySummary.longestContinuousSedentaryMinutes), caption: "sit")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Color.standCanvas)
        .navigationTitle("StandUp")
    }
}
```

Delete the complete private declarations of `StatusHero`, `IgnoreActionsView`, and `PermissionBanner`. Keep `SummaryTile` unchanged.

- [x] **Step 3: Run the focused check and verify green**

Run:

```sh
Checks/check-platform-session-ownership.sh
```

Expected: exit 0 with no output.

- [x] **Step 4: Add the ownership check to verification documentation**

Add the command after `Checks/check-history-correction-menu.sh` in `README.md` and `docs/DEVELOPMENT.md`:

```sh
Checks/check-platform-session-ownership.sh
```

Add this coverage bullet to `docs/DEVELOPMENT.md`:

```markdown
- explicit Watch ownership of live sessions and skip controls
```

- [x] **Step 5: Compile the iPhone target**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj \
  -target StandUpiOS \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

### Task 3: Disable Reminder Reconciliation On iPhone

**Files:**
- Modify: `Apps/Shared/StandUpAppModel.swift:17-40`
- Modify: `Apps/Shared/StandUpAppModel.swift:271-307`
- Modify: `Checks/StandUpSharedChecks/main.swift:22-375`
- Modify: `Checks/check-platform-session-ownership.sh`

- [x] **Step 1: Add a failing review-only reminder check**

Create a `StandUpAppModel` with `managesReminders: false`, change its local threshold, deliver newer synchronized settings through `MemorySync.onReceive`, await reminder reconciliation, and require `RecordingNotifier.plans` to remain empty.

- [x] **Step 2: Run the shared checks and verify red**

Run: `Checks/run-shared-checks.sh`

Expected: compilation fails with `extra argument 'managesReminders' in call`.

- [x] **Step 3: Add the reminder-management capability**

Add a `managesReminders` initializer parameter that defaults to `true`, store it on `StandUpAppModel`, and guard `reconcileReminders(now:)` before computing or executing a plan. Pass `false` from `StandUpiOSApp`; Watch keeps the default.

- [x] **Step 4: Strengthen the platform source contract**

Require the iPhone app to construct `StandUpAppModel(managesReminders: false)` and call `cancelSedentaryReminders()`. Scan the complete `Apps/iOS` directory for `model.ignore(` while retaining Watch startup and skip requirements.

- [x] **Step 5: Run both focused checks and verify green**

Run:

```sh
Checks/run-shared-checks.sh
Checks/check-platform-session-ownership.sh
```

Expected: all 14 shared checks pass and the platform source check exits 0.

### Task 4: Verify And Commit

**Files:**
- Verify: `Apps/iOS/DashboardView.swift`
- Verify: `Apps/iOS/StandUpiOSApp.swift`
- Verify: `Apps/Shared/StandUpAppModel.swift`
- Verify: `Checks/StandUpSharedChecks/main.swift`
- Verify: `Apps/Watch/StandUpWatchApp.swift`
- Verify: `Apps/Watch/WatchRootView.swift`
- Verify: `Checks/check-platform-session-ownership.sh`

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
swift build
```

Expected: 24 core checks and 14 shared checks pass, every source check exits 0, and the package build exits 0.

- [x] **Step 2: Build both application targets**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj \
  -target StandUpiOS \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build
```

Then run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj \
  -target StandUpWatch \
  -configuration Debug \
  -sdk watchsimulator \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: both application targets end with `** BUILD SUCCEEDED **`.

- [x] **Step 3: Commit the verified change**

```sh
git add Apps/Shared/StandUpAppModel.swift Apps/iOS/DashboardView.swift Apps/iOS/StandUpiOSApp.swift Checks/StandUpSharedChecks/main.swift Checks/check-platform-session-ownership.sh README.md docs/DEVELOPMENT.md docs/superpowers/specs/2026-07-10-platform-session-ownership-design.md docs/superpowers/plans/2026-07-10-platform-session-ownership.md
git commit -m "fix: enforce watch session ownership"
```
