# StandUp

StandUp is a local-first iPhone and Apple Watch app for automatic sedentary reminders.

## What It Does

- Apple Watch estimates low-activity sitting time automatically.
- Users can set the sedentary threshold from 15 to 120 minutes.
- Reminders repeat every 10 minutes after the threshold until the user stands or skips.
- Standing or walking for 2 continuous minutes resets the timer.
- In-progress sessions are restored after a local app restart.
- A bounded reminder series is scheduled only within active hours.
- iPhone shows overdue sitting intervals, corrections, and 7/30-day trends.
- Data stays local. There is no account system or server upload.

## Structure

- `Sources/StandUpCore`: tested core state machine and analytics.
- `Checks/StandUpCoreChecks`: executable verification suite for core behavior.
- `Apps/Shared`: storage, notification, motion, sync, and app model code.
- `Apps/iOS`: iPhone SwiftUI app.
- `Apps/Watch`: Apple Watch SwiftUI app.
- `project.yml`: XcodeGen project definition.

## Verify Core

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

## Open In Xcode

This repo uses XcodeGen for the iOS/watchOS project:

```sh
xcodegen generate
open StandUp.xcodeproj
```

See `docs/DEVELOPMENT.md` for setup and real-device validation notes.
