# Watch Settings Model Binding Design

## Goal

Keep the Apple Watch threshold control synchronized with the shared `StandUpAppModel` so settings received from the iPhone cannot be hidden or overwritten by stale view-local state.

## Problem

`WatchSettingsView` copies the threshold into `@State` only when the view appears. If WatchConnectivity later merges a newer threshold into `model.settings` while the settings page remains alive, the label and Slider continue to show the old value. The next Slider interaction can then publish that stale value as a new revision and overwrite the setting that just arrived.

The iPhone settings form needs local draft values because it coordinates multiple controls. The Watch view has only one threshold Slider, so duplicating the model value provides no editing benefit.

## Chosen Approach

Remove the Watch threshold `@State` and bind the Slider directly to `model.settings` through a computed `Binding<Double>`:

- the binding getter converts `model.settings.sedentaryThresholdMinutes` to `Double`;
- the binding setter calls `model.updateThreshold(minutes:)`;
- the displayed threshold reads directly from `model.settings`;
- the existing 15 through 120 range and 5-minute step remain unchanged.

This keeps `StandUpAppModel` as the single source of truth and deletes the `onAppear` and `onChange` synchronization lifecycle. Retaining mirrored `@State` with another model observer would preserve two sources of state and another feedback path. A cross-platform settings draft abstraction would add an unnecessary layer for one Watch control.

## Data Flow

For incoming changes:

1. WatchConnectivity delivers a synchronized state.
2. `StandUpAppModel` merges it and publishes `settings`.
3. SwiftUI invalidates `WatchSettingsView`.
4. The label and binding getter read the new threshold from the model.

For local edits:

1. The user moves the Slider.
2. The binding setter calls `updateThreshold(minutes:)`.
3. The model applies its existing normalization, persistence, and synchronization behavior.
4. The published model value drives the next render.

No storage schema, synchronization payload, model API, or visual layout changes.

## Error Handling

The binding introduces no new failure channel. Persistence and synchronization failures continue through the existing `operationalError` and retry UI. The model's unchanged-setting guard prevents redundant persistence if SwiftUI supplies the current value.

## Verification

Extend `Checks/check-platform-session-ownership.sh` to require the model-backed threshold binding and to reject a Watch-local threshold `@State`. Verify the source check fails before the view change and passes afterward.

Then run all core and shared checks, every existing source check, `swift build`, and both iOS and Watch simulator-SDK builds. The iOS target remains in the full verification set to confirm that the shared app-model contract is unchanged even though the view behavior is Watch-only.
