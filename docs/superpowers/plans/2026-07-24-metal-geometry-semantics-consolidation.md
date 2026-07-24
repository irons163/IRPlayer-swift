# Metal Geometry Semantics Consolidation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-metal-geometry-semantics-consolidation-design.md`.

## Phase 1: Audit and Baseline

- [x] Inventory Metal mesh/renderer policies, owners, tests, and project
  entries.
- [x] Record focused mesh/renderer baseline.

## Phase 2: Storage and Ownership

- [x] Add shared checked `IRMetalMeshStorage` arithmetic.
- [x] Move fisheye parameter normalization into a named mesh-owned value.
- [x] Move quad, viewport, and scale semantics into `IRMetalRenderer`.
- [x] Validate derived viewport, scale, and circle geometry.
- [x] Remove all four policy files and Xcode project entries.
- [x] Update local Metal architecture guidance.

## Phase 3: Test Architecture

- [x] Add focused `IRMetalMeshStorageTests`.
- [x] Remove duplicate mesh storage and wrapper-mirror tests.
- [x] Add exact texture-range, orientation, content-mode, and circle tables.
- [x] Add finite-input derived-overflow regressions.
- [x] Preserve real Metal buffer and render integration coverage.

## Phase 4: Verification

- [x] Run focused storage, mesh, renderer, and resource suites.
- [x] Run affected Metal/render boundaries under Thread Sanitizer.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run project, stale-symbol, warning, policy-count, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Mesh, renderer, and renderer-resource suites: 71 passed, 0 failed, 0
  skipped.
- Result bundle:
  `/private/tmp/irplayer-metal-geometry-baseline.xcresult`.

## Verification Results

- Focused storage, mesh, renderer, and renderer-resource suites: 71 passed,
  0 failed, 0 skipped.
- Focused result bundle:
  `/private/tmp/irplayer-metal-geometry-focused.xcresult`.
- Thread Sanitizer Metal storage, mesh, renderer, resource, target, and render
  boundaries: 114 passed, 0 failed, 0 skipped, with no sanitizer findings.
- Thread Sanitizer result bundle:
  `/private/tmp/irplayer-metal-geometry-tsan.xcresult`.
- Full iOS Simulator suite: 1,324 passed, 0 failed, 0 skipped.
- Full-suite result bundle:
  `/private/tmp/irplayer-metal-geometry-full.xcresult`.
- Generic iOS device Release build: passed; changed project sources emitted no
  warnings.
- Project integrity, stale-symbol, policy-count, shared-consumer, and whitespace
  checks: passed. The source tree contains 21 `*Policy.swift` files.
