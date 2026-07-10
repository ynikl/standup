# Platform Session Ownership Design

## Goal

Make every visible control act on the device that owns the sedentary session. Apple Watch remains the sole owner of live motion monitoring, reminder scheduling, and skip state; iPhone remains the review and configuration surface described by the product specification.

## Problem

The iPhone dashboard currently renders a live-session hero, a manual refresh button, permission status, and skip-reminder controls from its local `StandUpAppModel`. The iPhone app never starts `CoreMotionActivityService`, while the Watch app creates a separate model and owns motion ingestion.

Running engine sessions are intentionally local-only. `StandUpDataState` synchronizes settings and completed records, but excludes `SedentarySessionState`. Consequently, `model.ignore(...)` on iPhone only changes the idle iPhone engine and cannot pause the Watch session or its reminders. The iPhone live status is derived from that same non-authoritative engine and can disagree with Watch.

## Decision

Keep one live-session owner and remove the non-authoritative iPhone controls.

The iPhone app will:

- show today's completed-record summary, history, trends, and synchronized settings;
- stop requesting local notification permission at launch;
- stop ticking its local engine from launch and from a dashboard refresh button;
- construct its app model with reminder management disabled;
- remove any pending StandUp reminders left by an earlier app version;
- remove the live-session hero, skip controls, permission banner, and refresh button.

The Watch app will continue to:

- restore and refresh its local session;
- start Core Motion monitoring before requesting notification permission;
- show the live session status;
- execute every skip action locally against the authoritative session.

`StandUpAppModel` gains an injected reminder-management capability that defaults to enabled. Reminder reconciliation returns without touching the notification adapter when that capability is disabled. The core engine, persistence schemas, analytics, and WatchConnectivity payloads remain unchanged.

## Alternatives

### Add Cross-Device Commands

The iPhone could send skip commands and receive Watch snapshots through WatchConnectivity. A reliable design would need command identifiers, acknowledgements, idempotency, reachability handling, queued delivery, stale-command expiry, and real-device validation. That is disproportionate to the current MVP and would still leave ambiguous behavior when Watch is unavailable.

### Monitor On Both Devices

Starting motion monitoring and notifications on iPhone would make its controls locally effective, but it would create two independent estimates, duplicate reminders, and conflicting records. It also contradicts the existing product decision that Watch owns sensor monitoring.

## User Experience

The iPhone Today tab opens directly on the three daily summary metrics. It no longer claims to show the current sitting session or offers controls that cannot affect Watch. Live status and skip choices remain available in the Watch app's existing vertical pages.

No instructional placeholder replaces the removed controls. The remaining iPhone interface contains only working review and configuration workflows.

## Error Handling

Removing iPhone notification authorization also removes a permission warning for a capability that iPhone does not use. On launch, iPhone removes pending requests with the existing StandUp identifier prefix so reminders scheduled by an earlier version cannot survive the ownership change. This cleanup does not request notification permission. Existing storage and WatchConnectivity error handling is unchanged. Surfacing `operationalError` is a separate improvement because it affects all platforms and requires its own recovery design.

## Verification

Add a focused source contract check that requires:

- no `model.ignore`, `StatusHero`, `IgnoreActionsView`, `PermissionBanner`, or refresh toolbar in `Apps/iOS/DashboardView.swift`;
- no `requestPermissions` or local engine refresh in `Apps/iOS/StandUpiOSApp.swift`;
- iPhone constructs `StandUpAppModel` with reminder management disabled and cancels legacy pending reminders;
- Watch startup still starts motion monitoring and requests notification permission;
- `WatchRootView` still invokes `model.ignore(duration)`.

Add a shared behavior check that changes local settings and receives newer synchronized settings through a review-only model, then verifies its notification adapter received no replacement plans.

Run the complete core and shared checks, all existing source checks, `swift build`, and both iOS and Watch simulator-SDK builds. Real-device WatchConnectivity behavior is unaffected because the synchronization protocol does not change.
