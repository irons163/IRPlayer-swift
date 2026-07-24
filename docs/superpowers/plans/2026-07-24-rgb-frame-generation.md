# RGB Frame Generation Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-rgb-frame-generation-design.md`.

## Phase 1: Baseline and Geometry

- [x] Audit frame construction, dimension mutation, image fallback, Metal
  upload, render program, and submission call sites.
- [x] Record the pre-change focused render/frame baseline.
- [x] Add checked immutable video dimensions.
- [x] Replace separate mutable base dimensions with atomic replacement and
  snapshots.
- [x] Make Core Video and I420 frames report dimensions from their owned
  content.
- [x] Revoke I420 content on pool reuse.

## Phase 2: RGB Generation

- [x] Add explicit RGB24 and BGRA32 public formats.
- [x] Build one immutable checked RGB generation at initialization.
- [x] Preserve padded rows and prepare exact RGB24 RGBA8 upload bytes.
- [x] Make RGB dimensions immutable after publication.
- [x] Route UIKit image creation through the generation.

## Phase 3: Rendering Integration

- [x] Upload RGB24 as RGBA8 and BGRA32 as BGRA8 from one snapshot.
- [x] Migrate frame submission and renderer scale calculations to dimension
  snapshots.
- [x] Migrate 2D, fisheye, fish2pano, and render-state consumers.
- [x] Remove `IRVideoFrameRGBPolicy` and
  `IRMetalRendererPixelFormatPolicy`.
- [x] Update the public 2.0 migration guide and local architecture guidance.

## Phase 4: Tests

- [x] Cover dimension validation, atomic updates, type-owned dimensions, and
  concurrency.
- [x] Cover I420 pool-reuse content revocation.
- [x] Cover every RGB construction failure and padded-row success.
- [x] Cover exact RGB24 conversion and immutable snapshot behavior.
- [x] Cover RGB24/BGRA32 UIKit images and Metal texture bytes.
- [x] Preserve render program, fallback, texture-generation, multi-view, and
  mode integration behavior.

## Phase 5: Verification

- [x] Run focused video-frame, RGB, Metal, submission, program, state, and
  visual tests.
- [x] Run the changed frame/render boundary under Thread Sanitizer.
- [x] Run render and decoder integration suites.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run project metadata, stale-symbol, warning, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- RGB frame, Metal pixel/texture generation, frame submission, 2D,
  fish2pano, fish2persp, render-state, and view snapshot suites: 178 passed,
  0 failed, 0 skipped.

## Verification

Recorded on 2026-07-24 after implementation:

- Focused frame, RGB, Metal, submission, program, state, and snapshot suites:
  213 passed, 0 failed, 0 skipped.
- Thread Sanitizer frame, pool, RGB, Metal, submission, and render-state
  suites: 118 passed, 0 failed, 0 skipped, with no race diagnostics.
- Decoder, queue, pool, render-mode, multi-view, and distortion integration
  suites: 145 passed, 0 failed, 0 skipped.
- Full iOS Simulator suite: 1282 passed, 0 failed, 0 skipped.
- Generic iOS device Release build: passed. Warnings remain confined to the
  bundled FFmpeg framework headers.
- Package manifest, project metadata, stale-symbol, and whitespace checks:
  passed.
