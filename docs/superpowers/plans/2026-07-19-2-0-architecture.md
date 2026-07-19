# IRPlayer 2.0 Architecture Implementation Plan

**Goal:** Deliver a maintainable 2.0 player facade, playback core, backend boundary, typed observation API, and verified render/decode architecture.

**Design:** See `docs/superpowers/specs/2026-07-19-2-0-architecture-design.md`.

## Phase 1: Playback Core Boundary

- [x] Add `IRPlaybackBackend` and backend identity.
- [x] Make `IRAVPlayer` and `IRFFPlayer` conform without exposing concrete implementations publicly.
- [x] Add `IRPlaybackBackendCoordinator` with injected factory.
- [x] Add fake-based coordinator tests for routing, replacement, metrics, and reset.
- [x] Route `IRPlayerImp` commands and metrics through the coordinator.

## Phase 2: Swift-First Public API

- [x] Add `IRMediaSource` with URL, headers, video type, custom input, and backend preference.
- [x] Add validated `IRPlayerConfiguration`.
- [x] Add `load`, `stop`, and public read-only playback snapshot properties.
- [x] Add the preferred `IRPlayer` Swift name while retaining the 2.x migration facade.
- [x] Add source/configuration tests and update usage documentation.

## Phase 3: Typed Events And Lifecycle

- [x] Add `IRPlayerEvent` and cancellable observation tokens.
- [x] Make one event bridge feed typed observers and legacy notifications.
- [x] Consolidate lifecycle decisions into an explicit state owner.
- [x] Add event ordering, cancellation, and lifecycle tests.

## Phase 4: Backend And Decode Cleanup

- [x] Remove backend-to-facade concrete dependencies in favor of a host/event port.
- [x] Keep AVFoundation resource loading, observation, and frame output behind the backend boundary and verify its existing focused helpers.
- [x] Verify the existing FFmpeg read/display loop state owners independently from the player facade.
- [x] Remove project-owned FFmpeg API deprecation warnings where supported by the bundled version.
- [x] Run all AVPlayer and FFmpeg focused suites.

## Phase 5: Rendering And Interaction Completion

- [x] Complete and verify the existing render state/coordinator plan.
- [x] Move render-mode configuration out of `IRPlayerImp` switches.
- [x] Preserve the render state/coordinator boundaries, isolate mode configuration, and make view-to-player ownership weak.
- [x] Verify 2D, VR, fisheye, fish2pano, distortion, and multi4P tests.

## Phase 6: Release Quality

- [x] Fix framework-owned umbrella/header warnings.
- [x] Run `git diff --check`.
- [x] Run all new focused suites.
- [x] Run the full iOS Simulator suite.
- [x] Update 2.0 documentation and migration notes.
- [x] Record residual third-party warnings and risks.

## Verification Record

Completed on 2026-07-19:

- `git diff --check`: passed.
- Xcode project `plutil -lint`: passed.
- Full iOS Simulator suite on iPhone 17 / iOS 26.4: 938 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Remaining build warnings come from the bundled FFmpeg framework headers
  (`-Wquoted-include-in-framework-header` and upstream documentation warnings).
  Project-owned umbrella-header and deprecated audio channel-layout warnings were
  removed without editing vendored frameworks.
