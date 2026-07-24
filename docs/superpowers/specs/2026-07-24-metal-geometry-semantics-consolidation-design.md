# Metal Geometry Semantics Consolidation Design

## Context

Four Metal policy files remain as implementation mirrors:

- `IRMetalDistortionMeshPolicy`
- `IRMetalFisheyeMeshPolicy`
- `IRMetalRendererGeometryPolicy`
- `IRMetalRendererScalePolicy`

The two mesh policies duplicate identical checked byte-length and UInt16 index
conversion functions. Fisheye parameter normalization belongs only to the
fisheye mesh. Renderer quad, viewport, and content-scale calculations belong
only to `IRMetalRenderer`. Existing tests compare owners to policy mirrors
instead of testing one authoritative implementation.

Several functions validate source operands but not derived floating-point
values. Finite operands can still overflow during viewport subtraction,
render scaling, or aspect-ratio division.

## Goals

- Remove all four forwarding-only policy files.
- Replace duplicate mesh storage arithmetic with one shared, reusable
  `IRMetalMeshStorage` utility used directly by both mesh builders.
- Represent resolved fisheye geometry with a named, equatable owner-scoped
  value instead of an unlabeled tuple at call sites.
- Keep renderer quad, viewport, and scale semantics directly on
  `IRMetalRenderer`.
- Reject invalid or overflowing derived viewport/scale values.
- Normalize negative, off-texture, or overflowing fisheye circles to the
  existing centered fallback.
- Replace wrapper-comparison tests with exact tables and arithmetic-boundary
  assertions.

## Non-Goals

- Changing Metal pipeline, command queue, texture, command-resource, or
  distortion-target ownership.
- Changing valid mesh topology, vertex ordering, texture range, viewport
  orientation, or content-mode results.
- Changing shader code or public APIs.
- Combining unrelated RenderKit policies into this slice.

## Design

### Shared Mesh Storage Arithmetic

Add `IRMetalMeshStorage` as a small cross-mesh checked utility:

- positive element count and stride are required;
- multiplication must not overflow and must remain positive;
- indices must be exactly representable as `UInt16`.

Both mesh builders call this utility directly. Mesh classes no longer expose
forwarding test hooks.

### Fisheye Geometry

`IRMetalFisheyeMesh.Parameters` owns the five resolved values. Invalid texture
dimensions produce the existing zero/inert value. A custom circle is preserved
only when its positive radius fits on every side of the texture; otherwise the
existing centered maximum circle is used. Comparisons avoid overflowing
addition by checking against remaining extents.

### Renderer Geometry and Scale

`IRMetalRenderer` directly owns:

- the fixed quad vertex table for full/left/right texture ranges;
- top-left-flipped and bottom-left viewport conversion;
- aspect-fit, aspect-fill, and fill scale calculation.

Viewport conversion validates the derived origin and signed height. Scale
calculation validates intermediate ratios and the final scale; malformed,
overflowing, or underflowing values return the existing identity fallback.

## Test Architecture

- Add `IRMetalMeshStorageTests` with exact zero, negative, overflow,
  representability, and boundary cases.
- Keep mesh suites focused on parameter resolution and real Metal buffer
  construction.
- Keep renderer tests focused on exact quad/viewport/scale behavior.
- Add finite-input/derived-overflow regressions for fisheye geometry,
  viewports, and scales.
- Remove all owner-vs-policy comparison tests.

## Acceptance Criteria

- No source, test, or Xcode project reference to any deleted Metal policy
  remains.
- Both mesh builders use `IRMetalMeshStorage` directly.
- The source tree policy count falls from 25 to 21.
- Focused storage, mesh, renderer, and renderer-resource suites pass.
- Affected Metal/render boundaries pass under Thread Sanitizer.
- The full iOS Simulator suite passes.
- A generic iOS device Release build succeeds without changed-source
  warnings.
- Project, stale-symbol, policy-count, and whitespace audits pass.
