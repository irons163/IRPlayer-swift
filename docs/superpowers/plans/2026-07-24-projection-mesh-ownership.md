# Projection Mesh Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-projection-mesh-ownership-design.md`.

## Phase 1: Immutable Mesh Domain

- [x] Add `IRGLProjectionMesh`.
- [x] Add checked count and UInt16-index validation.
- [x] Add normalized equirectangular geometry.
- [x] Add pure VR and equirectangular mesh builders.
- [x] Validate complete meshes before returning them.

## Phase 2: Projection Integration

- [x] Replace VR static pointers with one `static let` mesh.
- [x] Replace equirectangular nested pointers with one optional mesh.
- [x] Publish equirectangular updates atomically.
- [x] Return coherent copy-on-write snapshots from export.
- [x] Remove all projection pointer allocation/copy/release code.

## Phase 3: Policy Consolidation

- [x] Move count, index, geometry, and builder decisions into the mesh domain.
- [x] Remove facade-to-policy forwarding.
- [x] Remove `IRGLProjectionVRPolicy.swift`.
- [x] Remove `IRGLProjectionEquirectangularPolicy.swift`.

## Phase 4: Tests

- [x] Replace wrapper-equivalence tests with mesh-domain assertions.
- [x] Add checked arithmetic and index-capacity tests.
- [x] Add exact VR/equirectangular count and winding tests.
- [x] Add equirectangular fallback and invalid-geometry tests.
- [x] Add immutable snapshot-across-update coverage.
- [x] Add concurrent VR creation/export coverage.
- [x] Add concurrent equirectangular update/export coverage.

## Phase 5: Verification

- [x] Run focused projection/mesh tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run projection, program-factory, and render-state integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata and whitespace validation.
- [x] Update projection guidance and the 2.0 completion audit.
- [x] Create a focused commit.

## Verification Record

Completed on 2026-07-24:

- Projection mesh focused suites: 27 passed, 0 failed.
- Thread Sanitizer focused suites: 27 passed, 0 failed, no race diagnostics.
- Projection, VR/fisheye program, program-factory, render-mode, and render-state
  integration suites: 115 passed, 0 failed.
- Full iOS Simulator suite: 1127 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package resolution, package dump/description, Xcode project listing,
  project property-list validation, stale-symbol search, and
  `git diff --check`: passed.
- The only build warning is Xcode's AppIntents metadata notice; changed project
  sources emit no warnings.
