# Idempotent Settings Updates Design

## Goal

Prevent unchanged settings assignments from creating a new synchronization revision, rewriting local storage, publishing to the peer device, or rescheduling reminders.

## Current Behavior

The iPhone and Watch settings views initialize local controls from `model.settings` in `onAppear` and observe those controls with `onChange`. Hydrating a non-default control value can call the app model even though the normalized setting is unchanged. Both app-model update methods always replace `settings`, advance `settingsUpdatedAt`, persist, publish, and reconcile reminders.

This is more than redundant work: a stale device can make its unchanged setting appear newer merely by opening the settings screen, causing that value to win a later WatchConnectivity merge.

## Selected Approach

Each app-model update method constructs its complete normalized candidate `StandUpSettings` value first. If the candidate equals the current settings, the method returns before changing any state or invoking side effects. Real changes preserve the existing revision, engine update, persistence, synchronization, snapshot, and reminder behavior.

The guard belongs in `StandUpAppModel`, which is the shared mutation boundary for both user interfaces. UI hydration flags and debouncing are intentionally excluded because they duplicate policy and do not protect non-UI callers.

## Verification

- Assigning a threshold that normalizes to the current threshold performs no save or sync publication.
- Assigning the current active window performs no save or sync publication.
- A genuinely changed threshold still updates settings, saves once, and publishes once.
- Existing core, shared-model, Watch lifecycle, package, and Watch simulator build checks remain green.

