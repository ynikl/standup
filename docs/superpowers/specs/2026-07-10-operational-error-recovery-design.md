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

1. **Storage:** A load failure retries `storage.load()`, merges the recovered synchronized state with newer in-memory revisions, preserves an in-memory session changed since the failure, and restores the engine and snapshot. Only after a successful read does it atomically persist the merged result. A save failure retries writing the current in-memory state. The unreadable file is never overwritten.
2. **Synchronization:** If either load or save recovery succeeded, or publishing previously failed, publish the current synchronized state without forcing another local write. If activation or decoding previously failed, asynchronously reactivate the bridge, keep retry progress visible until activation completes, and process its latest received application context.
3. **Reminders:** If reminder scheduling previously failed, invalidate the cached reminder plan, reconcile it again, and await the replacement task.

Each successful layer clears only its own failure. A failed retry refreshes that layer's message and leaves the Retry control available. `operationalError` keeps the current storage, synchronization, then reminder priority.

## Internal State

Replace the untyped persistence string with an internal failure value that distinguishes load from save failures while retaining the same user-visible message. This distinction is required because retrying a load must read and restore data, while retrying a save must preserve and write current memory.

Extract synchronization publishing from `persist(synchronize:)` into a private helper. Keep publish failures separate from receive/activation failures so success on one path cannot hide a failure on the other. `StandUpSyncing` reports activation success explicitly, allowing the model to clear an activation failure only after the bridge confirms recovery.

No persistence schema, WatchConnectivity payload, engine API, or notification identifier changes.

## iPhone Experience

When `operationalError` is non-nil, Settings shows an `App status` section before configuration controls:

- an `exclamationmark.triangle.fill` label and the exact current message;
- a full-width `Try again` command;
- a progress indicator and disabled command while retrying.

The status appears in Settings because storage and sync failures affect the whole app rather than a specific Today metric. It disappears automatically after all failed layers recover. The error is communicated with icon and text, not color alone. The Stepper draft values observe `model.settings`, so a successful reload replaces fallback values before another edit can write stale settings back.

## Watch Experience

The Watch status page keeps a stable 44-point header row. Its existing phase icon remains centered; a trailing warning button appears only when an operational error exists, with an invisible same-size leading spacer preserving alignment.

The warning button runs the same retry command. During retry it becomes a progress indicator and cannot be invoked again. It has an accessibility label of `Retry failed operation` and uses the current error as its accessibility hint. No long error string is placed in the compact visual layout.

## Error Handling

- A successful storage reload merges settings and records by their existing revisions. It restores the persisted engine session only when the in-memory session has not changed since the load failure; otherwise it preserves the current session. The merged state is saved, published, then reconciled if this model manages reminders.
- Synchronization retry is skipped while storage remains unhealthy so an empty fallback state cannot overwrite the peer.
- An activated WatchConnectivity session immediately reports activation success and reprocesses its latest application context. Otherwise async retry waits for the activation callback, keeping the command disabled. A still-invalid payload raises the receive error again; a corrected payload merges normally.
- Reminder retry is skipped while storage remains unhealthy for the same reason.
- Review-only iPhone models still never schedule reminders; they can retry storage and sync normally.
- Retry completion always resets the loading state with `defer`, including when a layer fails again.

## Verification

Extend shared behavior checks with recover-on-second-attempt adapters and verify:

- a load retry preserves newer synchronized settings and current session changes, saves only after the read succeeds, publishes the merged state, and clears the error;
- a save retry writes and publishes current state, then clears the error;
- a sync retry publishes current state and clears the error without an extra local save;
- an activation retry keeps progress visible, coalesces duplicate commands, and clears its error only after activation succeeds;
- a reminder retry replaces the plan and clears the error;
- concurrent retry calls do not create duplicate operations.

Add a source contract check requiring the iPhone Settings status section, loading/disabled Retry state, model-to-Stepper synchronization, Watch 44-point error control, and accessibility label/hint. Run all existing checks, `swift build`, and iOS/Watch simulator-SDK builds.
