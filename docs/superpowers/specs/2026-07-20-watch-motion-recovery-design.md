# Watch Motion Recovery Design

## Goal

Make Apple Watch sedentary tracking start reliably when the user is sitting and recover activity transitions missed while the app was suspended.

## Root Cause

The current Core Motion adapter maps every non-walking, non-running, non-cycling, and non-stationary sample to `.unavailable`. Core Motion can legitimately return an unknown or otherwise inconclusive sample while it calibrates, so the adapter turns a transient classification into a hard sensor failure. `SedentaryEngine` then pauses monitoring and clears the current session.

Core Motion also documents that live activity updates are not delivered while an app is suspended. The Watch app starts only live updates and never queries the activity history when it becomes active again, so transitions that happen while the display is asleep are missed.

## Selected Approach

Separate raw motion classification from sensor availability. Walking, running, and cycling map to `.active`; stationary maps to `.sedentary`; unknown, automotive-only, and otherwise unclassified samples produce no domain event. Only denied or restricted Motion authorization, an unavailable activity service, or a denied query emits `.unavailable`.

On launch and every transition back to the active scene, query Core Motion history before restarting live updates. Replay recognized observations in chronological order, then let the first live sample establish the current state. Persist the timestamp of the last accepted activity event in the engine session state and ignore observations at or before that timestamp. The recovery query starts after that timestamp, bounded by the current active-window start, so repeated launches do not recreate completed records.

The Watch status screen distinguishes calibration from a hard Motion access problem. An initial monitoring snapshot with no activity displays `Calibrating`; a sensor pause displays `Check Motion access`.

## Scope

- Add a pure motion-sample classifier and recovery normalizer in `Apps/Shared`.
- Extend local engine session state with the last accepted activity timestamp.
- Add history-aware lifecycle handling to the Watch app.
- Update Watch status text and icon semantics.
- Preserve the existing three domain activity signals and reminder behavior.

HealthKit, workout sessions, extended runtime sessions, and continuous background execution are outside this fix. Historical Core Motion recovery improves correctness after suspension but does not promise second-level background delivery.

## Risks

- Replaying the same historical transition more than once could duplicate records; timestamp persistence and stale-event rejection prevent this.
- Overnight active windows need the most recent window start rather than today's nominal start.
- Motion authorization can still be denied; the UI must remain paused and actionable in that case.

## Verification

- Pure checks cover stationary, active, inconclusive, ordering, clamping, and duplicate samples.
- Core checks cover stale activity rejection and persistence of the last activity timestamp after session completion.
- Shared checks cover recovery-start calculation from persisted state.
- Source checks cover Watch startup and active-scene restart behavior.
- All existing checks, `swift build`, XcodeGen generation, and a watchOS device build must pass.
