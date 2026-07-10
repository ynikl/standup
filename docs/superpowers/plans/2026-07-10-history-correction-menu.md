# History Correction Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every iPhone history record a visible, accessible menu that exposes all valid correction actions.

**Architecture:** Keep record mutation in `StandUpAppModel` and pass correction/restore closures into the row. Add a dedicated private menu view that renders either all domain correction reasons or the contextual restore action.

**Tech Stack:** Swift 6, SwiftUI `List` and `Menu`, SF Symbols, POSIX shell checks

---

### Task 1: Add A Failing History-Action UI Check

**Files:**
- Create: `Checks/check-history-correction-menu.sh`
- Test: `Apps/iOS/HistoryView.swift`

- [x] **Step 1: Create the source UI contract check**

```sh
#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
VIEW="$ROOT/Apps/iOS/HistoryView.swift"

for required in \
    'Menu {' \
    'ForEach(CorrectionReason.allCases, id: \.rawValue)' \
    'if record.isExcludedFromStats' \
    '.frame(width: 44, height: 44)' \
    '.accessibilityLabel(' \
    'model.correct(recordID: record.id, reason: reason)' \
    'model.restore(recordID: record.id)'
do
    if ! rg --quiet --fixed-strings "$required" "$VIEW"; then
        echo "History correction menu is missing: $required" >&2
        exit 1
    fi
done

if rg --quiet --fixed-strings '.swipeActions(' "$VIEW"; then
    echo "History correction actions must use the visible menu instead of crowded swipes" >&2
    exit 1
fi
```

- [x] **Step 2: Run the check and verify red**

Run: `sh Checks/check-history-correction-menu.sh`

Expected: exit 1 with `History correction menu is missing: Menu {`.

### Task 2: Implement The Contextual Correction Menu

**Files:**
- Modify: `Apps/iOS/HistoryView.swift:12`
- Modify: `Apps/iOS/DashboardView.swift:217`
- Modify: `README.md:27`
- Modify: `docs/DEVELOPMENT.md:9`
- Test: `Checks/check-history-correction-menu.sh`

- [x] **Step 1: Pass record actions into HistoryRow**

Replace the row and swipe-action block with:

```swift
HistoryRow(
    record: record,
    correct: { reason in
        model.correct(recordID: record.id, reason: reason)
    },
    restore: {
        model.restore(recordID: record.id)
    }
)
```

- [x] **Step 2: Add action closures and the menu to HistoryRow**

Use this complete row implementation:

```swift
private struct HistoryRow: View {
    let record: SedentaryRecord
    let correct: (CorrectionReason) -> Void
    let restore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(StandUpFormatting.timeRange(record))
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Text("+\(record.overageMinutes)m")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(record.isExcludedFromStats ? .secondary : Color.standAlert)
                HistoryActionsMenu(record: record, correct: correct, restore: restore)
            }

            HStack(spacing: 10) {
                Label("\(record.continuousSedentaryMinutes)m sitting", systemImage: "chair")
                if !record.ignoreEvents.isEmpty {
                    Label("\(record.ignoreEvents.count) skip", systemImage: "moon.zzz")
                }
                if record.isExcludedFromStats {
                    Label("excluded", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

- [x] **Step 3: Add the dedicated menu view**

```swift
private struct HistoryActionsMenu: View {
    let record: SedentaryRecord
    let correct: (CorrectionReason) -> Void
    let restore: () -> Void

    var body: some View {
        Menu {
            if record.isExcludedFromStats {
                Button(action: restore) {
                    Label("Restore to trends", systemImage: "arrow.uturn.backward")
                }
            } else {
                Section("Exclude from trends") {
                    ForEach(CorrectionReason.allCases, id: \.rawValue) { reason in
                        Button {
                            correct(reason)
                        } label: {
                            Label(reason.displayTitle, systemImage: icon(for: reason))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Actions for \(StandUpFormatting.timeRange(record))")
    }

    private func icon(for reason: CorrectionReason) -> String {
        switch reason {
        case .watchingMovie:
            return "film"
        case .meeting:
            return "person.2"
        case .alreadyStood:
            return "figure.stand"
        case .other:
            return "questionmark.circle"
        }
    }
}
```

- [x] **Step 4: Add the check to standard verification docs**

Add this command after `Checks/check-watch-startup-order.sh` in both verification command lists:

```sh
Checks/check-history-correction-menu.sh
```

Add this coverage bullet to `docs/DEVELOPMENT.md`:

```markdown
- complete and accessible iPhone history correction actions
```

- [x] **Step 5: Run the focused check and compile iPhone UI**

Run:

```sh
Checks/check-history-correction-menu.sh
```

Then run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj \
  -target StandUpiOS \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: the source check exits 0. The first iPhone build exposes the existing error `type 'ShapeStyle' has no member 'standAlert'` in `DashboardView.swift:217`.

- [x] **Step 6: Fix the existing iPhone compile blocker and rebuild**

Replace the permission banner image style with:

```swift
.foregroundStyle(Color.standAlert)
```

Rerun:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project StandUp.xcodeproj \
  -target StandUpiOS \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

### Task 3: Verify And Commit

**Files:**
- Verify: `Apps/iOS/HistoryView.swift`
- Verify: `Checks/check-history-correction-menu.sh`

- [x] **Step 1: Run all repository checks**

Run each command independently:

```sh
swift run StandUpCoreChecks
Checks/run-shared-checks.sh
Checks/check-watch-timeline.sh
Checks/check-watch-bundle-metadata.sh
Checks/check-watch-startup-order.sh
Checks/check-history-correction-menu.sh
swift build
```

Expected: 24 core checks and 13 shared checks pass, all source checks exit 0, and the package build exits 0.

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
git add Apps/iOS/HistoryView.swift Apps/iOS/DashboardView.swift Checks/check-history-correction-menu.sh README.md docs/DEVELOPMENT.md docs/superpowers/plans/2026-07-10-history-correction-menu.md
git commit -m "feat: expose complete history corrections"
```
