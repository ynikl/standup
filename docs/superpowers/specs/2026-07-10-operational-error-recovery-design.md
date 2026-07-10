# Operational Error Recovery Design

## Goal

Turn storage, WatchConnectivity, and reminder-scheduling failures from hidden diagnostic strings into visible, retryable product states on both iPhone and Apple Watch.

## Problem

`StandUpAppModel` already retains three failure channels and publishes the highest-priority message through `operationalError`. No view reads that property, so users cannot tell when local changes are not being saved, devices are out of sync, or reminders could not be updated.

The existing implicit recovery paths are inconsistent:

- a load failure disables persistence until an explicit edit overwrites the local file;
- a save or publish failure retries only after another user mutation;
- a reminder failure invalidates the cached plan and retries on a later Watch refresh.

Adding a passive banner would expose the failure without giving the user a reliable next step. Recovery must be defined before the UI is added.

## Recovery Model

`StandUpAppModel` will publish `isRetryingOperationalWork` and expose one async command:

```swift
func retryOperationalWork(now: Date = Date()) async
```

Only one retry may run at a time. A second invocation while retrying returns immediately.

The command processes currently failed layers in dependency order:

1. **Storage:** A load failure retries `storage.load()` and rehydrates settings, records, the engine session, and the snapshot. A save failure retries writing the current in-memory state. The unreadable file is never overwritten by the load-retry path.
2. **Synchronization:** If storage is healthy and synchronization previously failed, publish the current synchronized state without forcing another local write.
3. **Reminders:** If reminder scheduling previously failed, invalidate the cached reminder plan, reconcile it again, and await the replacement task.

Each successful layer clears only its own failure. A failed retry refreshes that layer's message and leaves the Retry control available. `operationalError` keeps the current storage, synchronization, then reminder priority.

## Internal State

Replace the untyped persistence string with an internal failure value that distinguishes load from save failures while retaining the same user-visible message. This distinction is required because retrying a load must read and restore data, while retrying a save must preserve and write current memory.

Extract synchronization publishing from `persist(synchronize:)` into a private helper. Normal persistence behavior remains unchanged; the helper only removes duplication so explicit retry can publish without rewriting storage.

No persistence schema, WatchConnectivity payload, engine API, or notification identifier changes.

## iPhone Experience

When `operationalError` is non-nil, Settings shows an `App status` section before configuration controls:

- an `exclamationmark.triangle.fill` label and the exact current message;
- a full-width `Try again` command;
- a progress indicator and disabled command while retrying.

The status appears in Settings because storage and sync failures affect the whole app rather than a specific Today metric. It disappears automatically after all failed layers recover. The error is communicated with icon and text, not color alone.

## Watch Experience

The Watch status page keeps a stable 44-point header row. Its existing phase icon remains centered; a trailing warning button appears only when an operational error exists, with an invisible same-size leading spacer preserving alignment.

The warning button runs the same retry command. During retry it becomes a progress indicator and cannot be invoked again. It has an accessibility label of `Retry failed operation` and uses the current error as its accessibility hint. No long error string is placed in the compact visual layout.

## Error Handling

- A successful storage reload restores the persisted engine session at the supplied retry time, then reconciles reminders if this model manages them.
- Synchronization retry is skipped while storage remains unhealthy so an empty fallback state cannot overwrite the peer.
- Reminder retry is skipped while storage remains unhealthy for the same reason.
- Review-only iPhone models still never schedule reminders; they can retry storage and sync normally.
- Retry completion always resets the loading state with `defer`, including when a layer fails again.

## Verification

Extend shared behavior checks with recover-on-second-attempt adapters and verify:

- a load retry restores persisted settings and clears the error without saving over the failed load;
- a save retry writes current state and clears the error;
- a sync retry publishes current state and clears the error without an extra local save;
- a reminder retry replaces the plan and clears the error;
- concurrent retry calls do not create duplicate operations.

Add a source contract check requiring the iPhone Settings status section, loading/disabled Retry state, Watch 44-point error control, and accessibility label/hint. Run all existing checks, `swift build`, and iOS/Watch simulator-SDK builds.
