# Animation plans

| Number | Title | Severity | Status |
| --- | --- | --- | --- |
| 001 | Expand navigation destinations from their tapped source | HIGH | DONE |
| 002 | Zoom timetable courses from their cards and replace the copy alert with a toast | HIGH | DONE |

## Recommended order

1. Plan 001 is complete and provides the shared SwiftUI navigation primitive.
2. Plan 002 is complete: timetable cards now use the shared source transition
   and course-code copy feedback is non-blocking.

## Dependencies

- Plan 001 has no external package dependency and requires iOS 18 only for the
  enhanced transition; older systems use its built-in fallback.
- Plan 002 depends on the helper completed in plan 001.
