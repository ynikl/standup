# History Correction Menu Design

## Goal

Expose every existing correction reason in iPhone history and show only actions that are valid for the record's current state.

## Current Behavior

The domain defines `watchingMovie`, `meeting`, `alreadyStood`, and `other`, but each history row exposes only Movie and Meeting through trailing swipe actions. Restore is shown even when a record is not excluded. Users therefore cannot complete the product-spec workflow for an already-standing misclassification or an uncategorized error.

## Selected Interaction

Each history row has one visible, icon-only `Menu` using the SF Symbol `ellipsis.circle`. The label occupies a stable 44 by 44 point frame and has an accessibility label containing the record's time range.

- An included record presents all `CorrectionReason.allCases` values using their existing display titles and a relevant SF Symbol.
- An excluded record presents only `Restore to trends`.

The menu replaces the crowded swipe actions. The row keeps its current information hierarchy, colors, list style, and density; no new screen, sheet, palette, or navigation path is introduced.

## Data Flow

`HistoryView` passes two closures into `HistoryRow`: one accepts a `CorrectionReason`, and one restores the record. The row owns only presentation and invokes those closures. `StandUpAppModel` remains the mutation, persistence, and synchronization boundary.

## Accessibility

The control uses SwiftUI `Menu` rather than an image with a custom tap gesture, preserving button semantics. Its 44-point frame meets the platform touch-target minimum, and its accessibility label identifies the associated history interval.

## Verification

- A source UI check requires `CorrectionReason.allCases`, contextual restore behavior, a 44-point menu target, and an accessibility label; it rejects the old swipe actions.
- The iPhone target must compile against the installed iOS Simulator SDK even though no iOS runtime is installed locally.
- Existing core, shared-model, Watch lifecycle, package, and Watch target checks remain green.

