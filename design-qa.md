# Design QA

- Source visual truth:
  - `/Users/xiaozhangwangxue/Downloads/Screenshot_20260916-083021.png`
  - `/Users/xiaozhangwangxue/Downloads/Screenshot_20260916-083036.png`
  - `/Users/xiaozhangwangxue/Downloads/Screenshot_20260916-083040.png`
  - `/Users/xiaozhangwangxue/Downloads/Screenshot_20260916-083044.png`
- Implementation screenshot: unavailable; the paired iPhone 12 is currently disconnected and no iOS Simulator runtime is installed.
- Intended viewport: iPhone 12, portrait.
- Source pixels: 920 x 2048 for the primary focus, timetable, and detail references; 552 x 2048 for the long query-center reference.
- State: week 2 timetable, focus screen, query center, and course detail.

## Full-view comparison evidence

The source screenshots were inspected and used to restore the original four-tab order, five-day timetable density, week controls, compact two-column query center, focus-page structure, and full course-detail information hierarchy. A current implementation capture could not be made because the physical device is unavailable.

## Focused region comparison evidence

Focused implementation comparison is blocked for the timetable header/weekend control and course-detail fields until the signed build can be launched on the iPhone.

## Findings

- [P0] Current build cannot be visually verified or interaction-tested on the target device.
  - Evidence: CoreDevice reports the paired iPhone 12 as unavailable, and it does not appear in the USB device tree.
  - Impact: spacing, safe-area behavior, tab-bar overlap, weekend toggle behavior, and course-detail navigation cannot receive a truthful final visual pass.
  - Fix: reconnect and unlock the iPhone, install the signed Release build, capture the same four states, and compare them with the supplied references.

## Comparison history

- Initial pass: source references inspected; implementation capture blocked by disconnected target device.
- Fixes already implemented from source evidence: original tab order and names, five/seven-day timetable toggle, original-style weekly grid, full course metadata persistence and detail screen, compact query center, focus layout, and official HFUT app icon.
- Post-fix visual evidence: pending device reconnection.

## Implementation checklist

- Install the signed Release app on the paired iPhone 12.
- Re-run academic synchronization once to populate newly preserved course-detail metadata.
- Capture timetable in five-day and seven-day modes.
- Open a course and verify every field and the three bottom actions.
- Open focus and query-center screens and compare density, safe areas, and tab-bar placement.

## Required fidelity surfaces

- Typography: code uses native Dynamic Type and system Chinese fonts; visual comparison pending.
- Spacing/layout rhythm: matched structurally to the references; device comparison pending.
- Colors/tokens: native adaptive background and Liquid Glass remain intentional iOS adaptations; device comparison pending.
- Image quality: official supplied HFUT emblem is used as a 1024 x 1024 opaque icon with safe margin.
- Copy/content: main navigation and course-detail labels now match the Android source and supplied screenshots.

final result: blocked
