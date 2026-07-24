# YUV Image Conversion Resource Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-yuv-image-conversion-resource-ownership-design.md`.

## Phase 1: Checked Conversion Generation

- [x] Add immutable checked RGB24 conversion configuration.
- [x] Add injectable context, scale, storage, and cleanup runtime.
- [x] Publish only fully constructed context/storage generations.
- [x] Replace FFmpeg image allocation with managed output bytes.

## Phase 2: Scoped Lifecycle

- [x] Add fixed-result scoped RGB conversion and typed outcomes.
- [x] Require exact converted output height.
- [x] Serialize conversion and terminal repeatable close.
- [x] Add diagnostics for context, capacity, and closed state.

## Phase 3: Integration and Policy Consolidation

- [x] Route `IRYUVConvertToImage` through the conversion owner.
- [x] Preserve existing helper signatures and snapshot behavior.
- [x] Move pure size, validation, and row-copy logic into `IRYUVTools.swift`.
- [x] Remove `IRYUVToolsPolicy.swift` and forwarding-equivalence tests.
- [x] Update Xcode project membership and repository guidance.

## Phase 4: Tests

- [x] Add configuration and construction-failure coverage.
- [x] Add partial-construction cleanup coverage.
- [x] Add success, reuse, scale failure, and incomplete-output coverage.
- [x] Add consumer rejection and invalid-source coverage.
- [x] Add concurrent close ordering, repeatable close, and deinit coverage.
- [x] Preserve real RGB24 and software-YUV snapshot integration coverage.

## Phase 5: Verification

- [x] Run conversion-owner and software-YUV focused tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run software-frame, Metal, snapshot, and decoder integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata, stale-symbol, and whitespace validation.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Software-YUV frame and platform-image suites: 35 passed, 0 failed.

## Verification Record

Recorded on 2026-07-24 after implementation:

- Conversion-owner, YUV-frame, and platform-image suites: 46 passed, 0 failed.
- The same focused suites with Thread Sanitizer: 46 passed, 0 failed, no race
  diagnostics.
- Conversion-owner, software-YUV, Metal pixel-renderer, and video-decoder
  integration suites: 101 passed, 0 failed.
- Full iOS Simulator suite: 1170 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Package/project metadata, stale-symbol, and whitespace validation: passed.
