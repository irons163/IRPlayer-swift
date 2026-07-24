# Fish2Pano Managed Lookup Generation Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-fish2pano-managed-lookup-generation-design.md`.

## Phase 1: Managed Generation

- [x] Add a complete immutable fish2pano pixel-map generation.
- [x] Validate geometry, antialias, texture count, and element counts.
- [x] Store lookup data in Swift-managed copy-on-write arrays.
- [x] Provide scoped, bounds-checked immutable buffer access.
- [x] Add generation diagnostics and focused tests.

## Phase 2: Publication

- [x] Build lookup arrays locally before generation publication.
- [x] Publish only the current request generation.
- [x] Replace pointer consume/release pairing with atomic take.
- [x] Remove consumed-pointer identity tracking and manual deallocation.
- [x] Cover take-once, stale work, regeneration, and concurrent behavior.

## Phase 3: Render-State Upload

- [x] Upload from the generation's coherent metadata and scoped buffers.
- [x] Validate lookup byte coverage before creating Metal textures.
- [x] Preserve the previous complete texture cache on rejected generations.
- [x] Preserve invalid, waiting, and ready render-state behavior.
- [x] Add real managed-generation Metal upload tests.

## Phase 4: Policy Consolidation

- [x] Move fish2pano output/layout/index validation into the domain.
- [x] Remove `IRGLFish2PanoShaderParamsPolicy.swift` and project references.
- [x] Remove stale pointer APIs, tests, and documentation.
- [x] Update Params and test ownership guidance.

## Phase 5: Verification

- [x] Run fish2pano generation/program/render-state focused tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run snapshot, render strategy, and Metal integration suites.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project, stale-symbol, warning, and whitespace validation.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Fish2pano program/shader-param and render-state suites: 43 passed, 0 failed.

## Verification Record

Recorded on 2026-07-24 after implementation:

- Fish2pano generation/program/render-state focused tests: 46 passed, 0 failed.
- The same focused tests with Thread Sanitizer: 46 passed, 0 failed, no race
  diagnostics or first-party warnings.
- Snapshot, render strategy, fish2pano, render-state, and Metal pixel-format
  integration suites: 137 passed, 0 failed.
- Full iOS Simulator suite: 1188 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package dump and Xcode project plist validation: passed.
- Stale fish2pano policy, pointer API, and mutable lookup-pointer scan across
  first-party Sources and Tests: clean.
- Changed-source warning and whitespace scans: clean. The generic build retains
  only Xcode's expected AppIntents metadata warning.
