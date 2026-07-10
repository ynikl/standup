# Watch Nonblocking Startup Design

## Goal

Start sedentary monitoring immediately when the Watch app launches, without waiting for the user to resolve the notification authorization prompt.

## Current Behavior

`StandUpWatchApp` awaits `model.requestPermissions()` before refreshing restored state or starting Core Motion. The notification prompt can remain onscreen indefinitely, so a user who has not answered it receives no motion monitoring even though notification permission and motion collection are independent capabilities.

## Selected Approach

Keep the existing SwiftUI task and dependency ownership. Reorder its operations to:

1. Refresh the model and reconcile restored state.
2. Start Core Motion updates.
3. Request notification authorization and await the user's response.

This requires no unstructured task, startup coordinator, or new cancellation policy. Motion callbacks continue to arrive through the existing main-actor handler. Notification authorization success, denial, and errors continue to update `permissionState.notificationsAllowed` through the app model.

## Scope

The change affects the Watch app only. It does not redesign notification onboarding, request motion authorization explicitly, or change iPhone startup because iPhone does not own the motion-monitoring session.

## Verification

- A source lifecycle check requires both `model.refresh()` and `motion.start` to appear before `await model.requestPermissions()` in the Watch startup task.
- Existing Watch timeline and bundle metadata checks remain green.
- Core and shared checks, package build, and Watch simulator build remain green.

