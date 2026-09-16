# Design QA

- Source visual truth:
  - `/Users/xiaozhangwangxue/Downloads/Screenshot_20260916-083021.png`
  - `/Users/xiaozhangwangxue/Downloads/Screenshot_20260916-083036.png`
  - `/Users/xiaozhangwangxue/Downloads/Screenshot_20260916-083040.png`
  - `/Users/xiaozhangwangxue/Downloads/Screenshot_20260916-083044.png`
- Target: iPhone 12, portrait, signed Release build.
- Device evidence:
  - `/tmp/hfut-final-installed.png`
  - `/tmp/hfut-options-release-loaded.png`
  - `/tmp/hfut-native-fail-rate.png`
  - `/tmp/hfut-web-login-fallback.png`
- Verified states: query center, options/security login, native fail-rate query, course detail, and WebVPN login fallback.

## Full-view comparison evidence

The signed Release build was installed and launched on the paired iPhone 12. The four-tab order, compact two-column query center, course-detail information hierarchy, bottom action group, options/security-login entry, safe areas, and tab-bar placement were compared against the supplied Android references. No clipping or tab-bar overlap was observed. The floating AssistiveTouch control visible in device captures is an iOS system overlay, not application UI.

## Focused region comparison evidence

- Query center: card height, two-column density, title sizing, and native destinations were checked on device. The official fail-rate destination opens as an in-app native screen instead of a placeholder web page.
- Course detail: metadata remains readable and the three original actions are present as full-width rows. Their destinations now use the corresponding official APIs.
- Security login: the native CAS form opens from Options. If direct device networking times out, the flow automatically switches to the official WebVPN/CAS page; an existing authenticated WebVPN session was recognized and the sheet dismissed back to the course detail.
- Schedule fidelity was covered by the earlier signed-device comparison; this pass did not change the timetable layout.

## Findings

- No P0 or P1 visual defects found in the changed surfaces.
- Live result contents for classmates, empty classrooms, course search, and fail rate still depend on a valid user session and server-side data. The entry points, request models, authentication-token handling, and error states are implemented and device-tested; account-specific returned records require the user to exercise the flows with their own credentials.

## Comparison history

- Initial pass: source references inspected; device verification was blocked while the iPhone was disconnected.
- Fidelity pass: original tab order and names, timetable controls and weekly grid, course metadata/detail screen, compact query center, focus layout, and HFUT icon were implemented.
- API pass: course actions and supported query-center items were moved from placeholder pages to the Android app's official endpoints; security login gained automatic WebVPN fallback.
- Final pass: signed Release installed and launched on iPhone 12; 14 device tests passed with zero failures.

## Required fidelity surfaces

- Typography: native Dynamic Type and system Chinese fonts remain legible on device.
- Spacing/layout rhythm: query cards, course actions, safe areas, and bottom navigation match the supplied information density without clipping.
- Colors/tokens: adaptive system colors and Liquid Glass are retained as the requested iOS adaptation.
- Image quality: the supplied HFUT emblem is used as an opaque 1024 x 1024 icon with a safe margin.
- Copy/content: navigation labels, course-detail labels, and supported official-query labels match the Android source.

final result: passed
