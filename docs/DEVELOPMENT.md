# StandUp Development

## Current Environment Note

A full Xcode install exists at `/Applications/Xcode.app`, but `xcode-select` points at the Command Line Tools by default. Either fix the selection once:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (no sudo needed), e.g.:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project StandUp.xcodeproj -scheme StandUpWatch \
  -destination 'platform=watchOS Simulator,name=StandUp Watch' build
```

Running the iOS app additionally requires the iOS platform component (Xcode > Settings > Components, or `xcodebuild -downloadPlatform iOS`).

## Verify Core Logic

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
- visible and retryable operational failures on iPhone and Watch

## Generate Xcode Project

Install XcodeGen, then run:

```sh
xcodegen generate
open StandUp.xcodeproj
```

After opening the project:

1. Set `DEVELOPMENT_TEAM` for `StandUpiOS` and `StandUpWatch`.
2. Adjust bundle identifiers if needed (the watch app id must stay prefixed by the iOS app id, and `WKCompanionAppBundleIdentifier` in `Apps/Watch/Info.plist` must match the iOS app id).
3. Run the `StandUpiOS` scheme on an iPhone simulator or device. The watch app is embedded and installs onto the paired Apple Watch automatically (or via the iPhone Watch app).
4. Use the `StandUpWatch` scheme to run the watch app alone on a watch simulator.

The companion pairing is what makes WatchConnectivity sync work: the watch app records sedentary sessions and publishes them through `updateApplicationContext`; the iPhone app receives and displays them. Two unrelated standalone apps cannot use WatchConnectivity.

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
