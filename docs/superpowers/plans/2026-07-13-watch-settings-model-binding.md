# Watch Settings Model Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Watch threshold label and Slider always reflect `StandUpAppModel.settings`, including settings received while the page remains alive.

**Architecture:** Keep `StandUpAppModel` as the only threshold state owner. Replace the Watch view's mirrored `@State` and lifecycle synchronization with a computed `Binding<Double>` that reads from the model and delegates writes to the existing idempotent `updateThreshold(minutes:)` API.

**Tech Stack:** Swift 6, SwiftUI, WatchConnectivity-driven `ObservableObject` state, POSIX shell source checks, Swift Package Manager, Xcode simulator SDK builds

---

### Task 1: Bind The Watch Threshold Directly To The Model

**Files:**
- Modify: `Checks/check-platform-session-ownership.sh:61-64`
- Modify: `Apps/Watch/WatchRootView.swift:172-196`
- Test: `Checks/check-platform-session-ownership.sh`
- Test: `Checks/run-shared-checks.sh`

- [x] **Step 1: Add the failing single-source contract**

Append these checks after the existing Watch skip-control assertion in `Checks/check-platform-session-ownership.sh`:

```sh
for required in \
    'private var thresholdBinding: Binding<Double>' \
    'get: { Double(model.settings.sedentaryThresholdMinutes) }' \
    'set: { model.updateThreshold(minutes: Int($0)) }' \
    'Text("\(model.settings.sedentaryThresholdMinutes)m")' \
    'Slider(value: thresholdBinding, in: 15...120, step: 5)'
do
    if ! rg --quiet --fixed-strings "$required" "$WATCH_ROOT"; then
        echo "Watch threshold control is missing model binding: $required" >&2
        exit 1
    fi
done

for forbidden in \
    '@State private var threshold' \
    'Slider(value: $threshold' \
    'threshold = Double(model.settings.sedentaryThresholdMinutes)' \
    '.onChange(of: threshold)'
do
    if rg --quiet --fixed-strings "$forbidden" "$WATCH_ROOT"; then
        echo "Watch threshold control must not mirror model state: $forbidden" >&2
        exit 1
    fi
done
```

- [x] **Step 2: Run the source check and verify red**

Run:

```sh
Checks/check-platform-session-ownership.sh
```

Expected: exit 1 with `Watch threshold control is missing model binding: private var thresholdBinding: Binding<Double>`.

- [x] **Step 3: Replace the mirrored Watch state with a model binding**

Replace `WatchSettingsView` in `Apps/Watch/WatchRootView.swift` with:

```swift
private struct WatchSettingsView: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Threshold")
                .font(.headline)

            Text("\(model.settings.sedentaryThresholdMinutes)m")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()

            Slider(value: thresholdBinding, in: 15...120, step: 5)
                .tint(.watchAccent)
        }
        .padding(.horizontal, 12)
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(model.settings.sedentaryThresholdMinutes) },
            set: { model.updateThreshold(minutes: Int($0)) }
        )
    }
}
```

- [x] **Step 4: Run the focused source check and verify green**

Run:

```sh
Checks/check-platform-session-ownership.sh
```

Expected: exit 0 with no output.

- [x] **Step 5: Verify the existing model update contract**

Run:

```sh
Checks/run-shared-checks.sh
```

Expected: all 20 shared checks pass, including unchanged-setting persistence and synchronization coverage.

- [x] **Step 6: Commit the behavior and regression check**

```sh
git add Apps/Watch/WatchRootView.swift Checks/check-platform-session-ownership.sh docs/superpowers/plans/2026-07-13-watch-settings-model-binding.md
git commit -m "fix: 修复 Watch 阈值状态回写"
```

### Task 2: Verify And Review The Completed Change

**Files:**
- Verify: `Apps/Watch/WatchRootView.swift`
- Verify: `Checks/check-platform-session-ownership.sh`
- Modify: `docs/superpowers/plans/2026-07-13-watch-settings-model-binding.md`

- [x] **Step 1: Run all package and source checks**

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
xcodebuild -project StandUp.xcodeproj -target StandUpiOS \
-configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Expected: the iOS target ends with `** BUILD SUCCEEDED **` for both simulator architectures.

Then run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj -target StandUpWatch \
-configuration Debug -sdk watchsimulator CODE_SIGNING_ALLOWED=NO build
```

Expected: the Watch target ends with `** BUILD SUCCEEDED **` for both simulator architectures.

- [x] **Step 3: Request independent code review**

Review the implementation against `docs/superpowers/specs/2026-07-13-watch-settings-model-binding-design.md`. The review must confirm:

- `StandUpAppModel.settings` is the only Watch threshold source;
- remote model changes immediately drive the label and Slider;
- local Slider edits still use `updateThreshold(minutes:)`;
- no storage, synchronization, or visual-layout contract changed;
- no Critical or Important findings remain.

Expected: the review reports no Critical or Important findings. If it reports one, do not mark this step complete; revise this plan with an explicit red-test, minimal-implementation, and green-verification sequence for that finding before editing code.

- [x] **Step 4: Record plan completion**

Mark every completed checkbox in this plan, then run:

```sh
rm -rf build
git diff --check
git add docs/superpowers/plans/2026-07-13-watch-settings-model-binding.md
git commit -m "docs: 记录 Watch 设置绑定验证"
```

Expected: the build directory is removed, the diff check exits 0, the commit succeeds, and `git status --short` shows only the user's untracked `StandUp.xcodeproj/`.
