# 001 — Expand navigation destinations from their tapped source

- **Status**: DONE
- **Commit**: 5316ef6d
- **Severity**: HIGH
- **Category**: Physicality & origin
- **Estimated scope**: 6 files, about 100 changed lines

## Problem

The Android app uses `sharedContainer` for frequently opened service tiles and
course cards, so a destination grows from the exact card the user touched and
returns to the same place. The SwiftUI port currently uses ordinary navigation
links, which makes the destination slide in from the edge and loses that spatial
relationship.

```swift
// ios/HFUTSchedule/HFUTSchedule/Views/ServicesView.swift:25 — current
NavigationLink(value: feature) {
    CompactFeatureTile(feature: feature)
}
```

```swift
// ios/HFUTSchedule/HFUTSchedule/Views/CourseDetailView.swift:121 — current
NavigationLink {
    OfficialCourseSearchView(courseName: course.name, code: details.code ?? "")
} label: {
    actionRow("其他教学班开课查询", icon: "magnifyingglass")
}
```

## Target

Add one reusable SwiftUI navigation-link wrapper that:

- uses `matchedTransitionSource(id:in:)` on the complete tappable source;
- uses `navigationTransition(.zoom(sourceID:in:))` on the destination;
- keeps the source and destination in the same private `Namespace`;
- falls back to a normal `NavigationLink` before iOS 18;
- falls back to a normal `NavigationLink` when `accessibilityReduceMotion` is
  enabled, so large viewport motion becomes a static system transition;
- does not add a fixed-duration animation, bounce, overlay, or navigation delay;
- leaves navigation interactive and reversible through the system back gesture.

Use the system zoom transition rather than a hand-authored timer. It preserves
the source origin, is interruptible, uses transform/opacity-composited motion,
and mirrors the entry path on exit.

## Repo conventions to follow

- Reusable SwiftUI surface helpers live in
  `ios/HFUTSchedule/HFUTSchedule/Components/GlassSurface.swift`.
- Interactive tiles already use `adaptiveGlass(..., interactive: true)`; keep
  that pressed-state feedback and do not add a second scale animation.
- Direct destination closures are already used in `CourseDetailView.swift` to
  prevent the outer navigation stack from intercepting typed route values.

## Steps

1. In `Components/GlassSurface.swift`, add an internal generic
   `SourceAnchoredNavigationLink<Destination, Label>` with a private namespace,
   a stable `sourceID: String`, destination/label view-builder closures, and an
   `accessibilityReduceMotion` environment value. On iOS 18+ with reduced motion
   off, pair `matchedTransitionSource` with `.navigationTransition(.zoom(...))`;
   otherwise render the same direct `NavigationLink` without spatial motion.
2. In `Views/ServicesView.swift`, replace each `NavigationLink(value:)` service
   tile with the wrapper and a stable ID `service-<feature.id>`. Keep shortcut
   deep-link navigation unchanged because it has no visible source element.
3. In `Views/DashboardView.swift`, replace quick-service tiles, snapshot buttons,
   toolbar buttons, and current-day course cards with stable source IDs. Convert
   feature value navigation to direct destinations and remove only the now-unused
   `navigationDestination(for: CampusFeature.self)` from this view.
4. In `Views/CourseDetailView.swift`, apply the wrapper to classmates and the
   three action rows. Use distinct IDs derived from the course ID and action name.
   Do not reintroduce typed route navigation.
5. In `Views/FeatureDetailView.swift`, apply the wrapper to native course-summary
   rows so course details grow from the selected row.
6. In `Views/AcademicRecordsView.swift`, apply the wrapper to grade analysis and
   grade detail rows, with stable term/course-derived IDs.

## Boundaries

- Do NOT change destination data loading, authentication, API calls, or route
  parameters.
- Do NOT change tab switching, sheet presentation, deep-link routing, or the
  course-detail destinations.
- Do NOT add third-party animation dependencies.
- Do NOT animate WebView loading overlays or continuous/high-frequency controls.
- Preserve all pre-existing uncommitted user changes.
- If these locations have drifted from commit `5316ef6d`, stop and report rather
  than replacing unrelated code.

## Verification

- **Mechanical**:
  - Run `xcodebuild` for the generic iOS Debug target with signing disabled and
    expect `BUILD SUCCEEDED`.
  - Build the existing test target and expect all existing tests to compile.
- **Feel check** on the connected iPhone:
  - Tap a query-center tile; the tile must expand from its exact grid location to
    full screen, with no intermediate destination.
  - Swipe back before the transition fully settles; motion must remain responsive
    and collapse toward the same tile.
  - Open a course and tap each of the three action rows; each must expand from the
    tapped row and land directly on its correct destination.
  - Enable Settings > Accessibility > Motion > Reduce Motion; repeat and confirm
    the large zoom is absent while navigation still works.
- **Done when**: source-anchored entry and symmetric return work for service tiles,
  course cards, course action rows, and grade rows without altering route results.

## Completion notes

- Added `SourceAnchoredNavigationLink` with the iOS 18 system zoom transition,
  normal-navigation fallbacks for iOS 17 and Reduce Motion, and adopted it at
  every source listed above.
- Converted dashboard and query-center feature routes to direct destinations;
  course actions remain direct and therefore cannot be intercepted by a typed
  intermediate route.
- Debug generic-device `build-for-testing` succeeded with signing disabled.
- `FeatureCatalogTests` passed 26/26 on the iOS 27.2 simulator.
