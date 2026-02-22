# ClipboardRefiner UI Improvements: Implementation Plan

Goal: Make action/result relationship explicit, improve result controls, support split view and input collapsing, clarify Explain mode, and add Diff toggle. Main focus: enable horizontal split layout.

## Checkpoints

- [x] 1) Add data model for run summary and UI state (action kind, preset snapshot, model, effort, duration, timestamps, explain output).
- [x] 2) Update action row: make Refine primary, Explain secondary (or More menu), label preset, and define preset scope messaging.
- [x] 3) Redesign result header: run summary line, Result/Explanation tabs or stacked panel, View: Result|Diff toggle.
- [x] 4) Add result controls row under Result label: Regenerate, Copy, Replace selection, and Undo toast after replace.
- [x] 5) Implement split view (Input left, Result right) + toggle + auto-collapse input behavior.
- [x] 6) Wire up logic: capture preset at run time, show locked snapshot, maintain last action and outputs, and keep history updated.
- [x] 7) Validate layout on small/large windows, adjust min/max sizes, and ensure empty/processing/error states remain clear.

## Progress Notes

- Status: Steps 1-7 complete. Recent work tightened split-view layout, popover anchoring, and diff styling.
