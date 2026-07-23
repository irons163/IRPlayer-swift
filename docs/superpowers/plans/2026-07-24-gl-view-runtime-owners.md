# GL View Runtime Owners Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-gl-view-runtime-owners-design.md`.

## Phase 1: Render Domain And Surface

- [x] Add a reentrant-safe render executor with diagnostics.
- [x] Add a terminal Metal surface session with complete-generation
  publication.
- [x] Cover valid prepare/resize, invalid size, unavailable resources, retry,
  reentrancy, concurrent access, and close.

## Phase 2: Frame And Mode Runtime

- [x] Add an explicit frame-submission session.
- [x] Add the aggregate render session for modes, viewport, interactions,
  surface, and frame state.
- [x] Move mode-specific render state behind that aggregate owner.
- [x] Implement real empty-buffer clearing.
- [x] Preserve 2D, flat multi, VR, fisheye, fish2pano, distortion, and multi4P
  routing.
- [x] Cover redraw, unsupported input, surface failure, concurrent submission,
  mode selection, reset, and terminal close.

## Phase 3: Snapshot And AV Layer

- [x] Add a cancellable/coalescing snapshot session with injected capture and
  save dependencies.
- [x] Add an AVPlayer-layer session with main-thread attachment, layout,
  gravity, and terminal teardown.
- [x] Cover coalescing, stale scheduled work, invalid capture geometry,
  replacement, detachment, and close.

## Phase 4: View Integration And Consolidation

- [x] Reduce `IRGLView` to UIKit/API translation over the owners.
- [x] Preserve existing internal compatibility entry points as computed
  forwarding APIs.
- [x] Move render strategies to a focused factory file.
- [x] Delete `IRGLViewPolicy` and `IRGLRenderStrategyPolicy`, moving decisions
  to the relevant owners.
- [x] Update presentation integration, project membership, and owner docs.

## Phase 5: Verification

- [x] Run expanded GL view/surface/frame/snapshot/AV-layer suites.
- [x] Run all affected render-mode/program/gesture suites.
- [x] Run focused suites with Thread Sanitizer.
- [x] Run the full iOS Simulator suite.
- [x] Run the generic iOS device build.
- [x] Run project/package validation and `git diff --check`.
- [x] Update the 2.0 completion audit and create a focused commit.

## Baseline

- Existing `IRGLViewSnapshotTests` and `IRGLViewRenderStateTests`: 52 tests.
- Full iOS Simulator suite: 1036 tests.

## Completion

- Added seven runtime-owner/factory source files and 34 focused owner tests.
- Focused display/runtime/render-mode/fish2pano suites: 123 passed with Thread
  Sanitizer.
- Thread Sanitizer exposed a fish2pano lookup-map publication race; lookup
  buffers now use immutable generations with locked transfer and independent
  consumed-buffer lifetime.
- Full iOS Simulator suite: 1069 passed.
- Generic iOS device build: passed.
