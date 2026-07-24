# RenderKit Domain Semantics Consolidation Design

Date: 2026-07-24

## Context

The final source policy inventory contains ten RenderKit files:

- `IRGLRenderModeFactoryPolicy`
- `IRGLRenderModeSettingPolicy`
- `IRGLFish2PerspShaderParamsPolicy`
- `IRGLShaderParamsPolicy`
- `IRGLProgramFactoryPolicy`
- `IRGLProgram2DFisheye2PanoPolicy`
- `IRGLProgram2DPolicy`
- `IRGLProgramMulti4PPolicy`
- `IRGLFisheyeTransformPolicy`
- `IRGLTransform2DPolicy`

Every policy is a parallel semantic layer in front of a mode, shader-parameter,
program, factory, or transform owner. Production types expose forwarding
wrappers, while several tests compare wrappers with policies instead of
asserting observable owner behavior.

The audit also found malformed-input hazards that matter in render and gesture
paths:

- fish2pano offset normalization and fisheye latitude/longitude normalization
  use repeated subtraction loops whose work is proportional to input
  magnitude;
- finite subtraction, multiplication, division, or conversion can derive
  infinity and publish it into transforms or shader state;
- 2D resize can preserve offsets outside newly computed bounds;
- multi-view viewport generation accepts non-finite geometry and discards the
  parent viewport origin;
- scale and scope helpers accept invalid ranges that can publish incoherent
  defaults.

## Goals

- Make render-mode configuration and construction belong to
  `IRGLRenderMode` and `IRGLRenderModeFactory`.
- Make checked GL integer conversion and perspective defaults belong to their
  shader-parameter owners.
- Make program construction, viewport, scaling, scrolling, and multi-view
  layout semantics belong to their program/factory owners.
- Make 2D and fisheye transform decisions named values nested in their
  transform-controller owners.
- Replace proportional normalization loops with constant-time remainder
  arithmetic while preserving boundary behavior.
- Validate every derived numeric value before publication.
- Clamp resized offsets to their newly computed bounds.
- Preserve parent viewport origin in multi-view layouts.
- Remove all ten policy files and every mirror-only test.
- Preserve render-session, Metal-resource, projection-mesh, shader-map,
  gesture, and controller ownership boundaries.

## Non-Goals

- Replacing the existing render-session or Metal renderer architecture.
- Changing projection tessellation, UV orientation, shader code, pixel
  formats, or command-resource ownership.
- Changing public render-mode classes or program factory entry points.
- Replacing scope and scale reference objects in this slice.
- Introducing new rendering modes.

## Design

### Render-mode ownership

`IRGLRenderMode` stores queued configuration as a private typed change
sequence. Only changes that affect an installed program are queued; wide-degree
metadata remains a mode property and no longer creates a no-op configuration
entry.

`IRGLRenderModeFactory` constructs its normal, panorama, fisheye, multi-panel,
VR, and distortion modes directly through focused owner helpers. The temporary
mode-plan policy and its implementation-mirror tests are removed.

### Shader-parameter ownership

`IRGLShaderParams` performs finite, bounded `GLint` conversion directly.
`IRGLFish2PerspShaderParams` applies its fixed output geometry, transform
flags, and field-of-view constants directly. Tests assert the resulting shader
state and delegate behavior rather than a parallel configuration value.

### Program and factory ownership

`IRGLProgramFactory` owns scale expansion, fisheye-scope adjustment, panel
defaults, and media-parameter admission. Range arithmetic is finite and
validated before a new range is installed.

`IRGLProgram2D` owns viewport conversion, bounds-status mapping, and
content-mode scaling. Derived ratios and `Float` conversions must remain finite
and positive.

`IRGLProgram2DFisheye2Pano` owns shader texture-size access and horizontal
offset normalization. Offset normalization uses
`truncatingRemainder(dividingBy:)`, preserves the existing signed-width result
for non-zero exact multiples, and rejects derived overflow.

`IRGLProgramMulti4P` owns viewport layout. It rejects malformed geometry,
preserves the input viewport origin, and continues to support arbitrary
positive child counts and selected-index absence.

### Transform ownership

`IRGLTransformController2D` nests its scope snapshot and decision values and
owns scale-range expansion, degree-unit conversion, update, scroll, and resize
semantics. All input and derived values are checked. Resize decisions clamp
scaled offsets to the recomputed bounds.

`IRGLTransformController3DFisheye` nests its normalized-scope, scroll, and
scale decisions and owns tilt defaults, aspect ratio, scaling, scrolling, and
scope normalization. Latitude and longitude wrap in constant time. Invalid
clocks, ranges, scales, or derived values are inert.

### Test architecture

- Remove wrapper-equality and policy-plan tests where owner integration already
  proves the behavior.
- Rename the two policy-only transform suites to owner-semantic suites.
- Add extreme finite, non-finite, derived-overflow, invalid-range, viewport
  origin, and resize-clamping coverage.
- Retain render-mode construction, shader update, program factory, gesture,
  transform-controller, fish2pano managed-generation, render-session, and
  real Metal integration coverage.

## Acceptance Criteria

- No source, test, or Xcode project reference to any `*Policy` type remains.
- The source policy inventory falls from ten to zero.
- Huge finite pano offsets and fisheye angles normalize in constant time.
- No owner publishes non-finite scale, offset, viewport, field-of-view, or
  range values from malformed or overflowing arithmetic.
- Multi-view child viewports preserve the parent origin.
- 2D resize never publishes offsets outside the recomputed bounds.
- Focused RenderKit, Thread Sanitizer, full simulator, generic iOS Release,
  project, warning, stale-symbol, policy-count, and whitespace gates pass.
