# Controller Domain Semantics Consolidation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-controller-domain-semantics-consolidation-design.md`.

## Phase 1: Audit and Baseline

- [x] Inventory controller policy definitions, owners, call sites, tests, and
  Xcode project entries.
- [x] Record focused controller baseline.

## Phase 2: Domain Consolidation

- [x] Move bounce values and checked geometry into `IRBounceController`.
- [x] Move checked ePTZ degree normalization into `IRePTZShiftController`.
- [x] Move base gesture semantics and actions into `IRGestureController`.
- [x] Move GL gesture semantics and actions into `IRGLGestureController`.
- [x] Remove all four policy files and Xcode project entries.
- [x] Update local controller architecture guidance.

## Phase 3: Test Architecture

- [x] Rename policy-oriented base gesture tests to controller tests.
- [x] Remove facade-to-policy mirror assertions.
- [x] Add complete direction and recognizer-state tables.
- [x] Add derived-coordinate overflow regression tests.
- [x] Preserve callback, recognizer, transform, and smooth-scroll integration
  coverage.

## Phase 4: Verification

- [x] Run focused controller suites.
- [x] Run affected controller/presentation boundaries under Thread Sanitizer.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run project, stale-symbol, warning, policy-count, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Bounce, ePTZ, base-gesture, and GL-gesture suites: 48 passed, 0 failed,
  0 skipped.
- Result bundle:
  `/private/tmp/irplayer-controller-semantics-baseline.xcresult`.

## Verification Results

- Focused controller semantics and callback suites: 55 passed, 0 failed,
  0 skipped.
- Focused result bundle:
  `/private/tmp/irplayer-controller-semantics-focused-2.xcresult`.
- Thread Sanitizer controller, smooth-scroll, sensor, and presentation
  boundaries: 105 passed, 0 failed, 0 skipped, with no sanitizer findings.
- Thread Sanitizer result bundle:
  `/private/tmp/irplayer-controller-semantics-tsan.xcresult`.
- Full iOS Simulator suite: 1,324 passed, 0 failed, 0 skipped.
- Full-suite result bundle:
  `/private/tmp/irplayer-controller-semantics-full.xcresult`.
- Generic iOS device Release build: passed with no changed-source warnings.
- Static audit: project plist valid, no deleted-policy/test references, four
  renamed-test project references, 25 remaining policy files, and no
  whitespace errors.
