# Watch Motion Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent transient Core Motion samples from pausing sedentary tracking and recover activity transitions missed while the Watch app was suspended.

**Architecture:** A pure shared classifier converts raw Core Motion flags into optional domain observations. `SedentaryEngine` persists the last accepted observation time for idempotent replay, while the Watch lifecycle queries history from that boundary before restarting live updates.

**Tech Stack:** Swift 6, Core Motion, SwiftUI, Swift Package Manager, XcodeGen

---

### Task 1: Pure Motion Classification

**Files:**
- Create: `Apps/Shared/MotionActivityClassification.swift`
- Modify: `Checks/StandUpSharedChecks/main.swift`
- Modify: `Checks/run-shared-checks.sh`

- [ ] Add checks proving stationary maps to `.sedentary`, walking/running/cycling map to `.active`, and unknown or automotive-only samples are omitted.
- [ ] Run `Checks/run-shared-checks.sh` and verify compilation fails because the classifier does not exist.
- [ ] Implement `MotionActivitySample`, `MotionActivityObservation`, and `MotionActivityClassifier` with chronological normalization, lower-bound clamping, and consecutive-signal deduplication.
- [ ] Run `Checks/run-shared-checks.sh` and verify all checks pass.

### Task 2: Idempotent Activity Recovery

**Files:**
- Modify: `Sources/StandUpCore/SedentaryEngine.swift`
- Modify: `Sources/StandUpCore/Settings.swift`
- Modify: `Checks/StandUpCoreChecks/main.swift`
- Modify: `Apps/Shared/StandUpAppModel.swift`
- Modify: `Checks/StandUpSharedChecks/main.swift`

- [ ] Add checks for stale event rejection, retained `lastActivityAt`, overnight active-window starts, and recovery boundaries.
- [ ] Run the focused core and shared checks and verify the new assertions fail.
- [ ] Persist `lastActivityAt`, reject non-increasing activity timestamps, preserve the timestamp when clearing a session, and expose the recovery query start from the app model.
- [ ] Re-run core and shared checks and verify green.

### Task 3: Core Motion History And Watch Lifecycle

**Files:**
- Modify: `Apps/Shared/MotionActivityService.swift`
- Modify: `Apps/Watch/StandUpWatchApp.swift`
- Modify: `Apps/Watch/WatchRootView.swift`
- Modify: `Checks/check-watch-startup-order.sh`

- [ ] Update the source check to require history-aware startup and active-scene restart.
- [ ] Run the source check and verify it fails against the old Watch lifecycle.
- [ ] Make the Core Motion adapter distinguish authorization failure from inconclusive samples, query history, then start live updates.
- [ ] Restart monitoring whenever the Watch scene becomes active and show `Calibrating` or `Check Motion access` as appropriate.
- [ ] Re-run all Watch source checks.

### Task 4: Full Verification And Commit

**Files:**
- Regenerate locally: `StandUp.xcodeproj`

- [ ] Run `swift run StandUpCoreChecks`.
- [ ] Run `Checks/run-shared-checks.sh` and all Watch/source shell checks listed in `docs/DEVELOPMENT.md`.
- [ ] Run `swift build`.
- [ ] Run `xcodegen generate`, then build `StandUpWatch` for the paired Apple Watch SDK without installing it.
- [ ] Review the diff, exclude `Apps/iOS/Info.plist` and the untracked generated Xcode project, and commit with `fix: recover watch motion tracking`.
