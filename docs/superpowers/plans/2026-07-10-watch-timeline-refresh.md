# Watch Timeline Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the Apple Watch status screen from restarting its refresh task during every SwiftUI render.

**Architecture:** Keep `TimelineView` as the minute scheduler, but store its initial date in view state so model publications cannot recreate the schedule from a new `Date`. Protect the lifecycle invariant with a focused source check and verify the real symptom in the watchOS simulator.

**Tech Stack:** Swift 6, SwiftUI, watchOS 26.5 simulator, POSIX shell checks

---

### Task 1: Add The Refresh Lifecycle Regression Check

**Files:**
- Create: `Checks/check-watch-timeline.sh`
- Test: `Apps/Watch/WatchRootView.swift`

- [ ] **Step 1: Write the failing source check**

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
VIEW="$ROOT/Apps/Watch/WatchRootView.swift"

rg -q '@State private var timelineStart = Date\(\)' "$VIEW"
rg -q 'TimelineView\(\.periodic\(from: timelineStart, by: 60\)\)' "$VIEW"
if rg -q 'TimelineView\(\.periodic\(from: \.now, by: 60\)\)' "$VIEW"; then
    echo "Watch timeline must not recreate its schedule from .now during body evaluation" >&2
    exit 1
fi
```

- [ ] **Step 2: Run the check and verify the red state**

Run: `sh Checks/check-watch-timeline.sh`

Expected: exit 1 because `WatchStatusView` has no stable `timelineStart` state yet.

### Task 2: Stabilize The Timeline Schedule

**Files:**
- Modify: `Apps/Watch/WatchRootView.swift:18`
- Test: `Checks/check-watch-timeline.sh`

- [ ] **Step 1: Add a stable timeline start date**

Add the state beside the environment model:

```swift
@State private var timelineStart = Date()
```

Use it in the schedule:

```swift
TimelineView(.periodic(from: timelineStart, by: 60)) { context in
```

- [ ] **Step 2: Run the focused check and verify green**

Run: `sh Checks/check-watch-timeline.sh`

Expected: exit 0 with no output.

- [ ] **Step 3: Run the existing automated checks**

Run: `swift run StandUpCoreChecks && sh Checks/run-shared-checks.sh && swift build`

Expected: 24 core checks pass, 11 shared checks pass, and the package build exits 0.

### Task 3: Verify The Original Symptom In The Simulator

**Files:**
- Verify: `Apps/Watch/WatchRootView.swift`

- [ ] **Step 1: Build the Watch target**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project StandUp.xcodeproj -target StandUpWatch -configuration Debug -sdk watchsimulator CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Install and launch on the booted Watch simulator**

Use `xcrun simctl install` with the built `.app`, then `xcrun simctl launch` with bundle identifier `com.standup.watch`. If the generated project still omits the standalone Watch metadata, first correct the tracked Watch target metadata rather than patching the installed product.

Expected: launch returns a process identifier and StandUp reaches its own UI.

- [ ] **Step 3: Verify rendering and resource usage**

Capture a screenshot with `xcrun simctl io <watch-udid> screenshot /tmp/standup-watch-fixed.png` and inspect the host process with `ps -axo pid,state,%cpu,%mem,command`.

Expected: the screenshot does not show the watchOS launch spinner, and CPU settles instead of remaining near 100%.

