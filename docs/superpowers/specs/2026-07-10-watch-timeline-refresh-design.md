# Watch Timeline Refresh Design

## Goal

Ensure the Apple Watch status screen reaches its first frame and refreshes at most once per scheduled minute instead of entering a render-triggered refresh loop.

## Root Cause

`WatchStatusView` constructs `TimelineView(.periodic(from: .now, by: 60))`. Each `model.refresh()` publishes a new snapshot and recomputes the view body, which evaluates `.now` again. The new timeline date changes `.task(id: context.date)`, starts another refresh, and repeats without waiting for the next minute.

Runtime sampling confirmed the loop through `WatchStatusView`'s task, `StandUpAppModel.refresh(now:)`, state publication, and persistence. The app remained alive while consuming about one CPU core and preventing watchOS from dismissing its launch placeholder.

## Selected Approach

Capture the timeline start date once in `WatchStatusView` state and pass that stable value to the periodic schedule. A model publication can then recompute the view without creating a new schedule identity. `context.date` changes only when the existing schedule advances to its next minute, so the current refresh task remains valid.

This preserves the current screen structure and refresh cadence. Replacing the timeline with a custom timer or changing app-model persistence is outside this focused fix.

## Verification

- A source regression check rejects `.periodic(from: .now, by: 60)` in the Watch status view and requires a stable timeline start value.
- Existing core and shared checks continue to pass.
- The Watch target builds for the watchOS simulator.
- After installation and launch, StandUp renders its UI instead of retaining the system spinner.
- The StandUp process settles near idle rather than continuously consuming a CPU core.

