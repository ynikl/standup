# Watch Nonblocking Startup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start Watch monitoring and restore model state before notification authorization can suspend startup.

**Architecture:** Preserve the existing SwiftUI task and move its nonblocking startup work before the authorization await. Add a source lifecycle check for deterministic regression coverage, then verify the simulator records its unavailable-motion state while the notification prompt is still unresolved.

**Tech Stack:** Swift 6, SwiftUI, POSIX shell, watchOS simulator

---

### Task 1: Add A Failing Startup-Order Check

**Files:**
- Create: `Checks/check-watch-startup-order.sh`
- Test: `Apps/Watch/StandUpWatchApp.swift`

- [ ] **Step 1: Create the lifecycle check**

```sh
#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/Apps/Watch/StandUpWatchApp.swift"

refresh_line=$(rg --line-number --max-count 1 --fixed-strings 'model.refresh()' "$APP" | cut -d: -f1)
motion_line=$(rg --line-number --max-count 1 --fixed-strings 'motion.start { signal in' "$APP" | cut -d: -f1)
permission_line=$(rg --line-number --max-count 1 --fixed-strings 'await model.requestPermissions()' "$APP" | cut -d: -f1)

if [ "$refresh_line" -ge "$permission_line" ] || [ "$motion_line" -ge "$permission_line" ]; then
    echo "Watch monitoring must start before notification authorization is awaited" >&2
    exit 1
fi
```

- [ ] **Step 2: Run the check and verify red**

Run: `sh Checks/check-watch-startup-order.sh`

Expected: exit 1 with `Watch monitoring must start before notification authorization is awaited`.

### Task 2: Make Notification Authorization Nonblocking

**Files:**
- Modify: `Apps/Watch/StandUpWatchApp.swift:12`
- Modify: `README.md:27`
- Modify: `docs/DEVELOPMENT.md:9`
- Test: `Checks/check-watch-startup-order.sh`

- [ ] **Step 1: Reorder the Watch startup task**

Replace the task body with:

```swift
.task {
    model.refresh()
    motion.start { signal in
        model.ingest(activity: signal)
    }
    await model.requestPermissions()
}
```

- [ ] **Step 2: Add the lifecycle check to both verification command lists**

Add this command after `Checks/check-watch-bundle-metadata.sh` in `README.md` and `docs/DEVELOPMENT.md`:

```sh
Checks/check-watch-startup-order.sh
```

Add this coverage bullet to `docs/DEVELOPMENT.md`:

```markdown
- Watch monitoring starts independently of notification authorization
```

- [ ] **Step 3: Run the lifecycle check and verify green**

Run: `Checks/check-watch-startup-order.sh`

Expected: exit 0 with no output.

### Task 3: Verify Source And Runtime Behavior

**Files:**
- Verify: `Apps/Watch/StandUpWatchApp.swift`
- Verify: `Checks/check-watch-startup-order.sh`

- [ ] **Step 1: Run the repository verification matrix**

Run each command independently:

```sh
swift run StandUpCoreChecks
Checks/run-shared-checks.sh
Checks/check-watch-timeline.sh
Checks/check-watch-bundle-metadata.sh
Checks/check-watch-startup-order.sh
swift build
```

Expected: 24 core checks and 12 shared checks pass, all Watch checks exit 0, and the package build exits 0.

- [ ] **Step 2: Build, reinstall, and launch the Watch app**

Build with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj \
  -target StandUpWatch \
  -configuration Debug \
  -sdk watchsimulator \
  CODE_SIGNING_ALLOWED=NO build
```

Then run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl uninstall AECCAAEE-2C44-48A6-A732-4FFD16185A8F com.standup.watch

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl install AECCAAEE-2C44-48A6-A732-4FFD16185A8F \
  build/Debug-watchsimulator/StandUp.app

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl launch AECCAAEE-2C44-48A6-A732-4FFD16185A8F com.standup.watch
```

Expected: build, install, and launch all exit 0.

- [ ] **Step 3: Verify motion state exists before resolving the notification prompt**

While the prompt remains onscreen, run:

```sh
DATA_CONTAINER=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun simctl get_app_container \
  AECCAAEE-2C44-48A6-A732-4FFD16185A8F \
  com.standup.watch data)

rg --fixed-strings '"pauseReason" : "sensorUnavailable"' \
  "$DATA_CONTAINER/Documents/standup-state.json"
```

Expected: the file contains `"pauseReason" : "sensorUnavailable"`, proving the simulator's Core Motion unavailable callback ran before authorization completed.

- [ ] **Step 4: Commit the verified change**

```sh
git add Apps/Watch/StandUpWatchApp.swift Checks/check-watch-startup-order.sh README.md docs/DEVELOPMENT.md docs/superpowers/plans/2026-07-10-watch-nonblocking-startup.md
git commit -m "fix: start watch monitoring before notification prompt"
```
