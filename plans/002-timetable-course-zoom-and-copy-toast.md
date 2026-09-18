# 002 — Zoom timetable courses from their cards and replace the copy alert with a toast

- **Status**: DONE
- **Commit**: 5316ef6d
- **Severity**: HIGH
- **Category**: Physicality & origin
- **Estimated scope**: 3 files, about 60 changed lines

## Problem

The connected iPhone is currently showing a screenshot of the weekly timetable.
Its course cards are still plain `Button`s that set a programmatic navigation
binding, so tapping one produces the default edge transition instead of growing
from the exact course card. In the destination, copying the course code presents
a modal alert with a confirmation button, interrupting the user.

```swift
// ios/HFUTSchedule/HFUTSchedule/Views/TimetableGridView.swift — current
Button { onSelect(item.course) } label: {
    TimetableCourseCard(course: item.course)
}
```

```swift
// ios/HFUTSchedule/HFUTSchedule/Views/CourseDetailView.swift — current
.alert("已复制课程代码", isPresented: $copiedCode) {
    Button("好", role: .cancel) {}
}
```

## Target

- A normal tap on any course card in the weekly timetable expands from that
  exact card into `CourseDetailView` using the shared
  `SourceAnchoredNavigationLink` introduced by plan 001.
- Returning collapses toward the same card and remains interactive through the
  system back gesture.
- The context-menu route remains available as a non-animated fallback; no
  existing course-detail entry point is removed.
- Copying a course code immediately updates the pasteboard, shows a compact
  bottom glass toast reading “已复制课程代码”, requires no confirmation, does not
  block touches, and dismisses automatically after about 1.6 seconds.
- Repeated taps restart the toast timeout cleanly. Leaving the screen cancels
  pending work.
- With Reduce Motion enabled, the navigation helper keeps its existing static
  fallback and the toast uses opacity only rather than moving from the edge.

## Steps

1. In `Views/TimetableGridView.swift`, wrap the visible course card in
   `SourceAnchoredNavigationLink`, using a stable source ID derived from the
   course UUID such as `timetable-course-<uuid>`, and create
   `CourseDetailView(course:)` directly in the destination closure. Preserve the
   existing frame, offset, button style, and context menu. Keep `onSelect` only
   for the context-menu fallback so normal taps no longer depend on the outer
   programmatic route.
2. Leave `ScheduleView`'s `selectedCourse` destination in place only for that
   context-menu fallback. Do not change week selection, gestures, timetable
   layout, add/sync sheets, or export alerts.
3. In `Views/CourseDetailView.swift`, remove the blocking copy alert. Add a
   bottom-aligned overlay toast that uses the existing `adaptiveGlass` surface,
   is excluded from hit testing, and stays clear of the safe area. Use a concise
   label with a checkmark icon.
4. Manage auto-dismissal with one cancellable `Task`: cancel the previous task,
   set the toast visible, wait about 1.6 seconds, and then hide it on the main
   actor. Cancel the task on disappearance. Do not add a confirmation action.
5. Use a short ease-out opacity-plus-bottom-move transition for the toast when
   Reduce Motion is off, and opacity only when it is on. Post a VoiceOver
   announcement after a successful copy.

## Boundaries

- Do NOT alter course data, detail API calls, authentication, or any destination
  parameters.
- Do NOT change the timetable card layout, colors, time calculations, overlaps,
  scroll behavior, weekend visibility, or week switching.
- Do NOT remove the context menu or its existing programmatic fallback.
- Do NOT introduce custom full-screen geometry, timers driving frame-by-frame
  animation, or third-party animation dependencies.
- Preserve all pre-existing uncommitted user changes.

## Verification

- **Mechanical**:
  - Run the generic iOS Debug `build-for-testing` with signing disabled and
    expect `BUILD SUCCEEDED`.
  - Run `FeatureCatalogTests` and expect all existing tests to pass.
- **Connected iPhone feel check**:
  - On the weekly timetable, tap cards in different columns and vertical
    positions; each detail screen must grow from the tapped card.
  - Swipe back before the transition settles and confirm it collapses toward the
    same card without jumping to another route.
  - Tap the course-code row; the bottom toast must appear without an alert or
    confirmation button, leave the detail screen usable, and disappear itself.
  - Tap the code repeatedly and confirm only one toast remains and the timeout
    restarts.
  - Enable Reduce Motion and confirm navigation still works and the toast does
    not slide.
- **Done when**: the installed iPhone build has source-anchored timetable course
  navigation and non-blocking course-code copy feedback without regressions.

## Completion notes

- Weekly timetable cards now open `CourseDetailView` through the shared system
  zoom transition while the context-menu route remains available.
- Course-code copy feedback is a bottom glass toast, ignores touches, announces
  success to VoiceOver, restarts its cancellable 1.6-second timeout on repeated
  taps, and uses opacity only when Reduce Motion is enabled.
- Generic-device Debug `build-for-testing` succeeded with signing disabled.
- `FeatureCatalogTests` passed 26/26 on the iOS 27.2 simulator.
