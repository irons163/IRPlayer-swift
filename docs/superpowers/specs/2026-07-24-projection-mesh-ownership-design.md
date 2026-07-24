# Projection Mesh Ownership Design

## Summary

The Metal projection layer still constructs meshes through OpenGL-era raw
buffers:

- `IRGLProjectionVR` lazily writes three unsynchronized static pointers and
  keeps those allocations for process lifetime.
- `IRGLProjectionEquirectangular` owns four pointer groups, including nested
  index buffers, and manually coordinates allocation, copying, replacement,
  and deallocation.

Both projections immediately copy those buffers into Swift arrays in
`exportMesh()`, which are then copied into Metal buffers. The raw-pointer
intermediate has no runtime benefit and creates the ownership, partial-failure,
and concurrency risks.

This change makes a projection mesh an immutable Swift value containing
positions, texture coordinates, and indices. A pure builder creates complete
meshes locally. VR publishes one thread-safe static value; equirectangular
projections atomically replace an instance generation after a complete rebuild.

## Problems

- VR initialization races when multiple projection instances are created or
  exported concurrently.
- A reader can observe one or two initialized VR pointers while the third is
  still missing.
- VR allocations have no normal release path.
- Equirectangular construction exposes many partial-allocation cleanup branches.
- Nested index-pointer capacity and byte-count bookkeeping obscure the actual
  mesh contract.
- `memcpy` adds no value because the consumer immediately creates Swift arrays.
- Equirectangular update and export have no synchronization boundary.
- Snapshot data has no explicit generation semantics during an update.
- `IRGLProjectionVRPolicy` and
  `IRGLProjectionEquirectangularPolicy` duplicate facade helpers through
  forwarding methods.

## Goals

- Remove all manually allocated projection mesh pointers.
- Introduce one immutable `IRGLProjectionMesh` value.
- Build a mesh completely before publication.
- Make VR static initialization thread-safe by construction.
- Make equirectangular update/export atomic and safe under concurrent access.
- Preserve current VR vertex/index counts, winding, coordinates, and texture
  mapping.
- Preserve current equirectangular default/fallback geometry and mapping.
- Keep exported snapshots valid after later projection updates.
- Validate arithmetic and UInt16 index capacity before allocating arrays.
- Consolidate geometry, count, index, and mesh construction logic into the
  projection domain.
- Remove both projection policy files and wrapper-equivalence tests.
- Add deterministic mesh, snapshot, update, and concurrency tests.

## Non-Goals

- Change the visual projection, sphere tessellation, winding, UV orientation,
  or Metal renderer interfaces.
- Change the VR slice count or equirectangular slice count.
- Cache arbitrary equirectangular parameter combinations globally.
- Add GPU-side procedural mesh generation.
- Change transform controllers, render modes, or viewport behavior.

## Components

### `IRGLProjectionMesh`

The mesh is a `Sendable` value with:

- `[SIMD3<Float>]` positions;
- `[SIMD2<Float>]` texture coordinates;
- `[UInt16]` indices.

Initialization validates matching position/texture counts and bounded,
finite attributes plus bounded, non-empty triangle index data. Arrays use
copy-on-write storage, so an exported generation remains valid when the owning
projection replaces its current mesh.

### `IRGLProjectionMeshBuilder`

The builder contains pure construction and validation:

- checked multiplication/addition;
- UInt16 index admission;
- equirectangular geometry normalization;
- VR sphere generation;
- fisheye/equirectangular sphere generation.

Every method returns either a complete mesh or `nil`; it never publishes
partial storage.

### `IRGLProjectionVR`

VR owns no pointers or mutable shared setup token. A `static let` complete mesh
is initialized once using Swift's thread-safe static initialization. Instances
expose counts and return the immutable shared arrays.

### `IRGLProjectionEquirectangular`

The instance stores one optional mesh behind a lock. Initialization and
fisheye-parameter updates build a candidate outside the lock, then replace the
generation in one short critical section. Export captures one generation under
the lock and returns it after unlocking.

## Geometry Compatibility

VR retains:

- 200 slices and 100 parallels;
- 20,301 vertices;
- 120,000 indices;
- the current six-index quad winding;
- the current vertical UV inversion.

Equirectangular retains:

- sphere radius 800;
- 180 slices;
- 32,761 vertices;
- 194,400 indices;
- current fisheye UV equations;
- fallback to image center and half of the smaller dimension when radius or
  center is zero or exceeds the image bounds;
- negative radius/center sentinels remain unavailable.

Non-finite or non-positive image dimensions remain unavailable rather than
creating a partial mesh.

## Concurrency And Snapshot Semantics

- VR static initialization is handled by the Swift runtime.
- Equirectangular builders operate only on local values.
- Publication swaps one immutable mesh while holding the instance lock.
- Export captures one mesh value while holding the same lock.
- Returned arrays are a coherent generation and are never mutated in place.

## Testing

- Builder tests cover checked arithmetic, UInt16 limits, invalid geometry,
  fallback normalization, counts, winding, and representative coordinates.
- VR tests create and export many instances concurrently.
- Equirectangular tests concurrently update and export the same projection.
- Snapshot tests retain an old export across replacement and verify it remains
  unchanged.
- Program-factory and render-state integration tests continue verifying that
  projection meshes reach Metal consumers.
- Focused concurrency suites run under Thread Sanitizer.

## Acceptance Criteria

- Projection sources contain no `UnsafeMutablePointer.allocate`,
  `deallocate`, or `memcpy`.
- VR contains no mutable static mesh state.
- Equirectangular owns one optional immutable mesh generation.
- Every export contains matching position/texture counts and valid indices.
- Concurrent create/update/export emits no race diagnostics.
- Both projection policy files are removed.
- Focused tests, Thread Sanitizer, projection/program integration tests, the
  full simulator suite, and a generic iOS device build pass.
