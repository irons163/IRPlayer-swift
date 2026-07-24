# AVPlayer Presentation Loop Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-avplayer-presentation-loop-ownership-design.md`.

## Phase 1: Baseline And Shared Driver

- [x] Record AVPlayer, session, facade, presentation, and display behavior.
- [x] Rename the smooth-scroll-specific display-link driver boundary for
  shared use.
- [x] Preserve main-thread installation, common-mode scheduling, active-only
  delivery, off-main close, and weak proxy lifetime.
- [x] Update smooth-scroll composition and tests to use the shared driver.

## Phase 2: AVPlayer Presentation Owner

- [x] Add explicit uninstalled, idle, active, and closed phases.
- [x] Add immutable presentation tokens, tick values, and atomic diagnostics.
- [x] Bind activation to the exact `IRAVPlayerSession.Token`.
- [x] Revoke a generation before pause/reset/close.
- [x] Serialize lifecycle mutation and invoke handlers outside locks.
- [x] Add injectable-driver failure, stale-tick, close, lifetime, and
  concurrency tests.

## Phase 3: Backend Integration

- [x] Remove raw display-link and proxy ownership from `IRAVPlayer`.
- [x] Keep normal playback idle and activate only the exact VR session.
- [x] Fence pixel-buffer lookup and render submission with both identities.
- [x] Deactivate before reset/detachment and close before session teardown.
- [x] Remove the unused `hasPixelBuffer` state.
- [x] Replace UIKit timer assertions with owner diagnostics.
- [x] Update Xcode project and ownership guidance.

## Phase 4: Verification

- [x] Run shared-driver, loop-owner, AVPlayer, session, smooth-scroll, facade,
  presentation, and display focused tests.
- [x] Run the focused suites with Thread Sanitizer.
- [x] Run AVPlayer/facade/display integration suites.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project, warning, stale-symbol, and whitespace validation.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- AVPlayer, AVPlayer session, facade runtime, presentation session, backend
  event router, and display runtime suites: 102 passed, 0 failed.

## Verification Record

Recorded on 2026-07-24 after implementation:

- Shared display-link, presentation-loop, AVPlayer, and smooth-scroll focused
  suites: 116 passed, 0 failed.
- Shared display-link, presentation-loop, AVPlayer/session, smooth-scroll,
  facade, and presentation suites under Thread Sanitizer: all 144 unique tests
  passed with no race or thread-performance diagnostics; the final off-main
  close regression was confirmed in a 9/9 driver rerun.
- AVPlayer, shared-driver, smooth-scroll, facade, backend-event, presentation,
  and display integration suites: 152 passed, 0 failed.
- Full iOS Simulator suite: 1253 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package manifest, Xcode project plist/object identities, stale symbols,
  native timer ownership, changed-source warnings, and whitespace checks:
  passed.
- Only bundled FFmpeg header and Xcode AppIntents metadata warnings remain.
