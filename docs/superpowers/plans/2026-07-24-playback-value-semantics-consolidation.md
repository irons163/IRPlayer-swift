# Playback Value Semantics Consolidation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-playback-value-semantics-consolidation-design.md`.

## Phase 1: Audit and Baseline

- [x] Inventory the remaining policy files, consumers, tests, and project
  entries.
- [x] Record the focused playback-value, payload, seek, image, and integration
  baseline.

## Phase 2: Value and Owner Semantics

- [x] Add immutable validated `IRPlaybackTimeRange`.
- [x] Move notification payload and numeric conversion semantics to their
  owner.
- [x] Move FFPlayer progress decisions to `IRFFPlayerRuntime`.
- [x] Move seek preparation and transitions to `IRFFDecoder`.
- [x] Move checked RGB byte-count arithmetic to the image platform boundary.
- [x] Remove the four policy files and Xcode project entries.
- [x] Update local architecture guidance.

## Phase 3: Test Architecture

- [x] Replace time-policy tests with range-value tests.
- [x] Remove payload, decoder-seek, and image wrapper-mirror tests.
- [x] Add exact boundary, malformed numeric, and derived-overflow tables.
- [x] Preserve notification, player-runtime, decoder, and real-image
  integration coverage.

## Phase 4: Verification

- [x] Run focused value, payload, player, decoder, image, and notification
  suites.
- [x] Run affected runtime/notification boundaries under Thread Sanitizer.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run project, stale-symbol, warning, policy-count, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Playback-time policy, model payload, platform image, player notification,
  facade runtime, AVPlayer semantics, FFPlayer runtime owner, decoder seek, and
  decoder operation suites: 125 passed, 0 failed, 0 skipped.
- Result bundle:
  `/private/tmp/irplayer-playback-value-baseline.xcresult`.

## Verification Results

- Focused value, payload, image, notification, facade runtime, AVPlayer
  semantics, FFPlayer runtime owner, decoder seek, and decoder operation
  suites: 128 passed, 0 failed, 0 skipped.
- Focused result bundle:
  `/private/tmp/irplayer-playback-value-focused-rerun.xcresult`.
- Thread Sanitizer playback-range, payload, notification, facade runtime,
  FFPlayer runtime owner, decoder seek, read-loop, and decoder operation suites:
  97 passed, 0 failed, 0 skipped, with no sanitizer findings.
- Thread Sanitizer result bundle:
  `/private/tmp/irplayer-playback-value-tsan.xcresult`.
- Full iOS Simulator suite: 1,327 passed, 0 failed, 0 skipped.
- Full-suite result bundle:
  `/private/tmp/irplayer-playback-value-full.xcresult`.
- Generic iOS device Release build: passed; changed project sources emitted no
  warnings.
- Project integrity, stale-symbol, dead-helper, policy-count, and whitespace
  checks: passed. The source tree contains 17 `*Policy.swift` files.
