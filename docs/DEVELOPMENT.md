# StandUp Development

## Current Environment Note

This workspace currently has Swift command-line tooling, but no full Xcode install selected. `xcodebuild` reports that the active developer directory is Command Line Tools. Because of that, the pure Swift package can be verified here, while iOS/watchOS app targets need a full Xcode install.

## Verify Core Logic

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

The check runner covers:

- default settings
- threshold normalization
- fixed skip durations
- threshold reminders
- 10-minute repeated reminders
- skip windows
- 2-minute activity reset
- sensor-unavailable pause behavior
- active-hours pause behavior
- daily summaries
- 7-day and 30-day trend windows
- local session restoration and legacy JSON migration
- bounded reminder planning within active hours
- shared app-model persistence and notification reconciliation
- stable Watch timeline scheduling across SwiftUI renders
- standalone Watch app bundle metadata
- Watch monitoring starts independently of notification authorization
- complete and accessible iPhone history correction actions
- explicit Watch ownership of live sessions and skip controls

## Generate Xcode Project

Install XcodeGen, then run:

```sh
xcodegen generate
open StandUp.xcodeproj
```

After opening the project:

1. Set `DEVELOPMENT_TEAM` for `StandUpiOS` and `StandUpWatch`.
2. Adjust bundle identifiers if needed.
3. Run `StandUpiOS` on an iPhone simulator or device.
4. Run `StandUpWatch` on an Apple Watch simulator or paired watch.

## Real-Device Validation Checklist

- Sitting still starts counting automatically.
- Reminder appears around the configured threshold.
- Ignoring for 2 hours suppresses repeat reminders and keeps the session alive.
- Dismissing a reminder without standing repeats after 10 minutes.
- Walking or standing for 2 minutes ends the session.
- History appears on iPhone with correct intervals and overage minutes.
- Excluding a history item removes it from trend stats.
- A full day of watch use has acceptable battery impact.

The code pre-schedules reminders so timer delivery does not depend on a foreground minute tick. Core Motion delivery while the watch app is suspended still requires real-device validation; the command-line checks do not prove watchOS background execution.
