# AVPlayer Domain Semantics Consolidation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-avplayer-domain-semantics-consolidation-design.md`.

## Phase 1: Audit and Baseline

- [x] Inventory all AVPlayer policy definitions, wrappers, call sites, tests,
  and project references.
- [x] Record focused AVPlayer backend/session/presentation baseline.

## Phase 2: Domain Consolidation

- [x] Move playback and time semantics directly into `IRAVPlayer`.
- [x] Move track parsing and fallback semantics into `IRAVPlayerTracks`.
- [x] Move error snapshots and mapping into `IRAVPlayerLifecycle`.
- [x] Remove all four policy files and Xcode project entries.
- [x] Update local architecture guidance.

## Phase 3: Test Architecture

- [x] Add focused `IRAVPlayerSemanticsTests`.
- [x] Move pure policy tests out of the backend integration suite.
- [x] Replace wrapper comparisons with table-driven behavioral assertions.
- [x] Cover complete state, time, track, redirect, asset, and error boundaries.
- [x] Preserve integration and source compatibility coverage.

## Phase 4: Verification

- [x] Run focused semantic, backend, session, and presentation-loop suites.
- [x] Run changed AVPlayer boundaries under Thread Sanitizer.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run project, stale-symbol, warning, policy-count, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- AVPlayer backend, session, and presentation-loop suites: 89 passed, 0
  failed, 0 skipped.
- Result bundle:
  `/private/tmp/irplayer-av-semantics-baseline.xcresult`.

## Verification Results

- Focused semantic, backend, session, and presentation-loop suites: 92
  passed, 0 failed, 0 skipped.
- Focused result bundle:
  `/private/tmp/irplayer-av-semantics-focused.xcresult`.
- Thread Sanitizer: 92 passed, 0 failed, 0 skipped, with no sanitizer
  findings.
- Thread Sanitizer result bundle:
  `/private/tmp/irplayer-av-semantics-tsan.xcresult`.
- Full iOS Simulator suite: 1,323 passed, 0 failed, 0 skipped.
- Full-suite result bundle:
  `/private/tmp/irplayer-av-semantics-full.xcresult`.
- Generic iOS device Release build: passed with no changed-source warnings.
- Static audit: project plist valid, no deleted-policy references, four test
  project references, 29 remaining policy files, and no whitespace errors.
