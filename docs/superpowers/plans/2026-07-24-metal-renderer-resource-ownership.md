# Metal Renderer Resource Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-metal-renderer-resource-ownership-design.md`.

## Phase 1: Baseline and Resource Model

- [x] Audit renderer, surface, distortion, adapter, and focused test call sites.
- [x] Record the pre-change Metal and render-owner test baseline.
- [x] Add typed pipeline, quad-buffer, and bootstrap-failure values.
- [x] Add injectable renderer-resource construction dependencies.
- [x] Build one immutable complete renderer-resource generation.

## Phase 2: Renderer and Surface Bootstrap

- [x] Construct renderers only from complete resource generations.
- [x] Replace mutable optional renderer resources with read-only non-optional
  access.
- [x] Pass the surface command queue into renderer construction.
- [x] Propagate exact renderer bootstrap failures through the surface phase.
- [x] Preserve the internal convenience initializer through the same builder.

## Phase 3: Distortion Target Ownership

- [x] Add a synchronized distortion target session with coherent generations.
- [x] Reuse canonical sizes and atomically replace only on successful
  allocation.
- [x] Add reset, terminal close, deinit, and immutable diagnostics.
- [x] Route distortion rendering through the target owner.
- [x] Move distortion geometry validation into the domain and remove
  `IRMetalRendererDistortionPolicy`.

## Phase 4: Tests

- [x] Cover complete renderer-resource publication.
- [x] Cover cache, library, function, pipeline, and quad-buffer failures.
- [x] Prove failed bootstrap never publishes a renderer or surface resources.
- [x] Prove surface and renderer share the exact command queue.
- [x] Replace mutable-missing-pipeline tests with construction-boundary tests.
- [x] Cover distortion reuse, replacement, failure preservation, reset, close,
  deinit, and concurrency.
- [x] Preserve all successful render-mode and pixel-format integration tests.

## Phase 5: Verification

- [x] Run renderer-resource, distortion, surface, and command-resource focused
  tests.
- [x] Run the changed ownership boundary under Thread Sanitizer.
- [x] Run render-owner, strategy, render-state, pixel-format, and frame-texture
  integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run project metadata, stale-symbol, warning, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Metal renderer pixel-format, distortion, frame-texture, command-resource,
  render-strategy, and render-state suites: 79 passed, 0 failed.

`IRGLRuntimeOwnerTests.swift` contains several XCTest classes rather than an
XCTest class named after the file, so the final focused command must select
`IRGLMetalSurfaceSessionTests` and the other relevant contained classes
explicitly.

## Verification

Recorded on 2026-07-24 after implementation:

- Renderer-resource, distortion-target, pixel-format, distortion-render, and
  Metal-surface focused suites: 83 passed, 0 failed, 0 skipped.
- Render ownership and mode integration suites: 189 passed, 0 failed, 0
  skipped.
- Changed Metal ownership boundary under Thread Sanitizer: 112 passed, 0
  failed, 0 skipped; no data-race, Thread Sanitizer, thread-performance, or
  priority-inversion diagnostics.
- Full iOS Simulator suite: 1276 passed, 0 failed, 0 skipped.
- Generic iOS device build with code signing disabled: passed.
- Xcode project plist, Swift package metadata, stale-symbol, warning,
  whitespace, and project-entry checks: passed.
