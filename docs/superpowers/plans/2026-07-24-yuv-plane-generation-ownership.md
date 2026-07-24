# YUV Plane Generation Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-yuv-plane-generation-ownership-design.md`.

## Phase 1: Checked Managed Plane Domain

- [x] Add checked I420 plane layouts and ceiling chroma dimensions.
- [x] Add reusable Swift-managed three-plane storage.
- [x] Add immutable copy-on-write plane snapshots.
- [x] Add fixed-result scoped plane bytes and value diagnostics.
- [x] Add generation-bound image conversion.

## Phase 2: Frame And Consumer Integration

- [x] Publish complete plane generations from `setFrameData`.
- [x] Make invalid input and flush revoke active generations.
- [x] Preserve capacity across frame-pool reuse.
- [x] Replace frame pointer getters with `planeSnapshot()`.
- [x] Upload all Metal textures inside one snapshot borrow.
- [x] Keep image cache publication generation-fenced.

## Phase 3: Policy Consolidation

- [x] Move frame validation and capacity decisions into the plane domain.
- [x] Remove `channelPixels` and public luma/chroma pointers.
- [x] Remove frame-local channel-filter wrappers.
- [x] Remove `IRFFAVYUVVideoFramePolicy.swift`.
- [x] Remove `IRYUVChannelFilterPolicy.swift`.

## Phase 4: Tests

- [x] Replace pointer mutation and pointer-identity assertions.
- [x] Add invalid line-size and overflow coverage.
- [x] Add odd-dimension and padded-row coverage.
- [x] Add capacity reuse and growth coverage.
- [x] Add immutable snapshot-across-update coverage.
- [x] Add concurrent update/snapshot coverage.
- [x] Update image-cache and Metal texture/render coverage.
- [x] Extend real software decode coverage with coherent plane assertions.

## Phase 5: Verification

- [x] Run focused YUV-frame/Metal/video-decoder tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run display, decoder, queue, and FFPlayer integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata, stale-pointer, and whitespace validation.
- [x] Update frame/render guidance and the 2.0 completion audit.
- [x] Create a focused commit.

## Verification Record

Completed on 2026-07-24:

- Software-YUV frame, Metal pixel-format, video-decoder, and real software
  decode focused suites: 114 passed, 0 failed.
- The same 114 tests under Thread Sanitizer: passed with no race diagnostics.
- Frame pool/queue, decoder session/runtime, Metal/render-state/mode, and all
  FFPlayer runtime-owner integration suites: 267 passed, 0 failed.
- Full iOS Simulator suite: 1138 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package resolution, package dump/description, Xcode project listing,
  project property-list validation, stale-pointer/stale-policy search, and
  `git diff --check`: passed.
