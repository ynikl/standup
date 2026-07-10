# Reliable Monitoring Design

## Goal

Make the existing sedentary-monitoring flow deterministic across timer ticks, app restarts, notification scheduling, and phone/watch synchronization without introducing an unverified watchOS background runtime mechanism.

## Scope

This change covers four connected reliability problems:

- Continuous active movement must clear a session after two minutes even when Core Motion does not emit a second identical activity callback.
- Scheduled reminders must respect the sedentary threshold, an active ignore window, repeat cadence, and the configured active-hours boundary.
- An in-progress sedentary session must survive local app-model recreation.
- Settings and record corrections must converge when iPhone and Apple Watch exchange stale state.

The change does not add HealthKit, workout sessions, extended runtime sessions, cloud storage, accounts, or a new UI. Those require a separate real-device design and validation cycle.

## Architecture

`StandUpCore` remains the authority for time-based behavior. The engine will expose a codable session-state value and a pure reminder-plan value. System adapters may persist or execute those values, but they will no longer reproduce threshold and active-window rules themselves.

Local persistence and WatchConnectivity will use separate payloads:

- Local state contains settings, records, revision metadata, and the current engine session state.
- Sync state contains settings, records, and revision metadata, but never imports the peer's running engine session into the local engine.

This preserves Apple Watch as the owner of its sensor session while still allowing both devices to converge on user-editable data.

## Core Session State

The engine session state contains the existing session dates and ignore events plus the latest activity signal. It does not contain `Calendar`; the receiving engine restores the state with its local calendar and current settings.

When `.activity(.active)` arrives, the engine records the active candidate start and latest signal. A later `.tick` checks the elapsed active duration. If it reaches `activeClearMinutes`, the engine closes the session exactly as a later `.active` event would. A sedentary or unavailable event clears or pauses that candidate according to the existing state-machine rules.

The engine exposes its session state after every event. Restoring malformed or temporally impossible state is rejected in favor of an empty session, rather than allowing negative or future durations into analytics.

## Reminder Planning

The engine produces an ordered list of reminder intents from its current session and a supplied `now` date. Each intent has a stable identifier, delivery date, and notification reason.

Planning rules:

1. No plan is produced without a sedentary session or while monitoring is paused or active movement is in progress.
2. The first reminder is never earlier than the sedentary threshold.
3. If an ignore window extends beyond that threshold, the first reminder moves to the ignore end.
4. Repeat reminders follow at `repeatReminderMinutes` intervals.
5. No reminder is planned at or after the end of the current active window.
6. The plan is capped at 60 requests so it stays below the platform's pending-notification limit while leaving room for unrelated app notifications.

The notification adapter replaces all pending StandUp reminders atomically from the caller's perspective: remove identifiers with the StandUp prefix, then add the current plan. Activity, unavailable sensors, and an empty plan therefore cancel obsolete reminders.

## Persistence And Migration

The local JSON schema gains an optional session-state field and revision metadata. Decoding remains compatible with the current file: missing session state means an empty session, missing settings revision means the oldest revision, and missing record revision falls back to the record's end time.

The app model persists after an engine event because the event may change session state even when no completed record is emitted. It publishes through WatchConnectivity only when synchronized fields change; minute-only session ticks no longer resend the full history.

Load failures do not silently overwrite the unreadable file. The model starts with an empty in-memory state, records an operational error for diagnostics, and waits for a successful explicit change before writing new state.

## Synchronization

Settings carry `settingsUpdatedAt`. Incoming settings replace local settings only when their revision is newer.

Each sedentary record carries `modifiedAt`. A newly completed record uses its end time. Correcting or restoring a record sets `modifiedAt` to the edit time. Records are merged by UUID, selecting the version with the newest `modifiedAt`; equal revisions keep the local version. This resolves the current permanent divergence where each side retains its own copy of the same UUID.

The sync payload remains a latest-state application context. Deletions are not introduced because the product currently supports exclusion and restoration rather than record deletion.

## Error Handling

Notification scheduling reports failures back to the app model instead of discarding them with `try?`. Storage and sync failures are logged and represented as a small operational-error state; they do not crash monitoring. Core planning remains pure and cannot fail.

## Verification

The existing executable check suite will gain focused checks for:

- a tick clearing two minutes of continuous active movement;
- sedentary activity interrupting an active-clear candidate;
- a pre-threshold ignore never scheduling an early reminder;
- reminders ending at the active-window boundary;
- repeat reminder cadence and the 60-request cap;
- session-state encode/decode and restoration;
- backward decoding of the current persisted JSON shape;
- newer settings winning and stale settings being ignored;
- the newest correction or restoration winning record merge conflicts.

`swift run StandUpCoreChecks` and `swift build` must pass. Full iOS/watchOS compilation and real-device background validation remain explicitly unverified until a complete Xcode installation and paired hardware are available.
