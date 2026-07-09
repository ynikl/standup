# StandUp Product Spec

## Product Goal

StandUp is a local-first Apple Watch and iPhone app that estimates sedentary time automatically, nudges the user to stand, and gives them a concrete history of overdue sitting periods.

## MVP Scope

- Apple Watch tracks low-activity sedentary sessions automatically.
- Users configure sedentary threshold from 15 to 120 minutes in 5-minute steps.
- Default threshold is 45 minutes.
- Active hours default to 09:00-22:00.
- Repeated reminders fire every 10 minutes after the threshold is reached.
- A session resets only after 2 continuous minutes of active movement.
- Users can skip reminders for 15 minutes, 30 minutes, 1 hour, 2 hours, or until tomorrow.
- iPhone shows today, historical overdue intervals, 7-day trends, and 30-day trends.
- iPhone history records can be excluded when the app misclassifies a movie, meeting, or already-standing period.
- Data is stored locally. There is no account system, server upload, or cloud sync in the MVP.

## Intentional Constraints

- The app does not promise exact chair-sitting detection. It estimates sedentary state from low activity and standing/walking signals.
- The app prioritizes battery life and stable watch behavior over second-level reminder precision.
- HealthKit stand-ring data is not the primary real-time source in this version.
- Focus modes, calendar meetings, sleep state, and driving state are not part of the MVP automation. Users can skip reminders manually.
- If the watch is unavailable, not worn, or sensor data cannot be read, monitoring pauses and does not backfill sedentary time.

## Architecture

- `StandUpCore`: pure Swift package with state machine, settings, records, corrections, and analytics.
- `Apps/Shared`: app model, local JSON storage, local notifications, Core Motion activity mapping, and WatchConnectivity bridge.
- `Apps/iOS`: iPhone SwiftUI app for configuration and review.
- `Apps/Watch`: Apple Watch SwiftUI app for at-a-glance timer and quick reminder control.

## Core State Machine

The engine accepts three event types:

- `activity(.sedentary | .active | .unavailable)`
- `tick`
- `ignore(duration)`

It produces:

- a current snapshot for UI
- optional notification intent
- completed sedentary records

The state machine is tested through `StandUpCoreChecks`.
