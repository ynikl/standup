# State-Change Persistence Design

## Goal

Avoid encoding and atomically writing the complete local StandUp state for foreground timer ticks that do not change the monitoring session, while preserving every write required for restart recovery.

## Current Behavior

`StandUpAppModel.apply` persists after every engine event. The Watch status screen produces a tick each minute while visible, so an unchanged session still rewrites `standup-state.json`. The state file stores session dates rather than a continuously increasing elapsed-minute counter, so these writes do not improve recovery.

## Selected Approach

Each public event method captures `engine.sessionState` immediately before ingesting its event. It compares that value with the state after ingestion and passes the result to `apply`. `apply` persists only when the session changed or the output contains a completed record.

The comparison stays in the app model rather than adding a last-written-state cache or teaching the storage adapter domain rules. This keeps write intent explicit and avoids a second source of truth.

## Preserved Behavior

- Activity starting or changing a session remains persistent.
- Ignore actions remain persistent.
- Threshold and repeat-reminder ticks remain persistent because they update reminder dates.
- Active-clear and active-window ticks remain persistent because they close or clear a session.
- Settings, corrections, restoration, and incoming synchronization keep their existing explicit persistence paths.
- Every tick still publishes a fresh UI snapshot, so displayed elapsed minutes continue to advance.

## Error Handling

Skipping an unchanged write does not clear an existing storage error. A required write still uses the existing failure handling and disables further automatic persistence until an explicit user change retries storage.

## Verification

- A pre-threshold tick after a sedentary session begins must not increase the storage save count.
- A threshold-reaching tick must increase the save count and persist `thresholdReachedAt`.
- Existing core, shared-model, Watch lifecycle, package-build, and Watch simulator build checks must continue to pass.

