# Metal Command Texture Lifetime Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-metal-command-texture-lifetime-design.md`.

## Phase 1: Immutable Frame Texture Generations

- [x] Add typed NV12, BGRA, I420, and RGB texture layouts.
- [x] Retain Core Video wrappers and source pixel buffers in complete
  generations.
- [x] Reject partial or unsupported texture construction.
- [x] Add immutable generation diagnostics.

## Phase 2: Command Resource Ownership

- [x] Add collecting, submitted, and cancelled command-resource states.
- [x] Cache one generation per frame identity inside a command.
- [x] Move resources to one completion-owned generation on submission.
- [x] Make cancellation, completion, and deinit release repeatable.
- [x] Reject collection and duplicate submission after terminal transition.

## Phase 3: Renderer Integration

- [x] Route every command-producing render path through one resource scope.
- [x] Prepare frame textures through the scope in pixel renderers.
- [x] Reuse one generation across multi-view and distortion-eye draws.
- [x] Submit resources before command-buffer presentation and commit.
- [x] Preserve all existing pixel-format and render-mode behavior.

## Phase 4: Tests

- [x] Add generation format, plane, retention, and failure coverage.
- [x] Add same-frame caching and failed-construction coverage.
- [x] Add submission, completion, cancellation, duplicate-operation, and
  deinit coverage.
- [x] Add actual Metal command-buffer completion coverage.
- [x] Update direct pixel-renderer tests for explicit command resources.
- [x] Preserve all 2D, mesh, fish2pano, distortion, and YUV integration tests.

## Phase 5: Verification

- [x] Run command-resource and Metal pixel-format focused tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run render-owner, strategy, distortion, and YUV integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata, stale-symbol, and whitespace validation.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Metal pixel-format, distortion, render-strategy, render-owner, and
  software-YUV suites: 84 passed, 0 failed.

## Verification Record

Recorded on 2026-07-24 after implementation:

- Command-resource, frame-generation, pixel-format, and distortion focused
  suites: 67 passed, 0 failed.
- The same 67 focused tests under Thread Sanitizer: 67 passed, 0 failed, no
  Thread Sanitizer race diagnostics. The iOS Simulator Metal driver emitted
  Thread Performance Checker QoS notices from `Metal` and `MTLSimDriver`.
- Metal render-owner, strategy, distortion, pixel-format, command-resource,
  frame-generation, and software-YUV integration suites: 101 passed, 0 failed.
- Full iOS Simulator suite: 1185 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Xcode project plist, command submission, Core Video texture-call ownership,
  stale helper, compiler-warning, Thread Sanitizer diagnostic, and whitespace
  scans: passed. The device build retained the existing informational
  AppIntents metadata warning because the framework does not depend on
  AppIntents.
