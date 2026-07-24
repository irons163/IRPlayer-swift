# RenderKit Domain Semantics Consolidation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-renderkit-domain-semantics-consolidation-design.md`.

## Phase 1: Audit and Baseline

- [x] Inventory the final ten policies, owners, consumers, tests, and project
  entries.
- [x] Audit arithmetic, normalization, viewport, configuration, and transform
  publication boundaries.
- [x] Record the focused ten-suite baseline.

## Phase 2: Owner Semantics

- [x] Move typed configuration and mode construction to mode owners.
- [x] Move GL conversion and perspective defaults to shader-parameter owners.
- [x] Move factory range and parameter semantics to `IRGLProgramFactory`.
- [x] Move viewport, scale, pano, and multi-view semantics to program owners.
- [x] Move 2D transform decisions to `IRGLTransformController2D`.
- [x] Move fisheye transform decisions to
  `IRGLTransformController3DFisheye`.
- [x] Replace proportional wrapping loops and reject derived overflow.
- [x] Remove all ten policy files and Xcode project entries.
- [x] Update RenderKit architecture guidance.

## Phase 3: Test Architecture

- [x] Remove wrapper/policy mirror tests.
- [x] Rename transform policy suites to owner-semantic suites.
- [x] Add extreme finite, non-finite, derived-overflow, invalid-range,
  viewport-origin, and resize-clamping cases.
- [x] Preserve mode, factory, shader, gesture, transform, render-session, and
  Metal integration coverage.

## Phase 4: Verification

- [x] Run focused RenderKit owner and integration suites.
- [x] Run affected RenderKit boundaries under Thread Sanitizer.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run project, stale-symbol, warning, policy-count, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Render-mode build/factory, shader params, perspective params, program
  factory, 2D, pano, multi4P, fisheye-transform policy, and 2D-transform policy
  suites: 139 passed, 0 failed, 0 skipped.
- Result:
  `/private/tmp/irplayer-renderkit-baseline.xcresult`.

## Verification Results

Completed on 2026-07-24:

- Focused RenderKit owner/integration suites: 198 passed, 0 failed, 0
  skipped.
- Latest-generation fish2pano cancellation regression: passed normally and
  under Thread Sanitizer after stale work became cooperatively cancellable.
- Thread Sanitizer RenderKit owner/integration suites: 151 passed, 0 failed,
  0 skipped, with no sanitizer findings.
- Full iOS Simulator suite: 1345 passed, 0 failed, 0 skipped.
- Generic iOS device Release build: passed with 0 errors and 0 warnings in
  the result bundle.
- Project parsing, changed Swift parsing, stale-symbol, policy-count,
  magnitude-proportional loop, and whitespace checks: passed. The source tree
  contains no `*Policy.swift` files.
- Results:
  `/private/tmp/irplayer-renderkit-focused-final.xcresult`,
  `/private/tmp/irplayer-renderkit-tsan-final-v2.xcresult`,
  `/private/tmp/irplayer-renderkit-full-final.xcresult`, and
  `/private/tmp/irplayer-renderkit-release-final.xcresult`.
