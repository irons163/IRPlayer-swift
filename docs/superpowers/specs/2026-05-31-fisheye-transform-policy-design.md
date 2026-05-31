# Fisheye Transform Policy Design

## Summary

This slice extracts low-risk, render-independent 3D fisheye transform decisions from `IRGLTransformController3DFisheye` into an internal pure helper. The goal is to make scope range selection, scale/FOV math, scroll bounds, and lat/lng normalization testable without touching Metal drawing or public render APIs.

The new helper is internal-only and keeps existing public API, class names, render mode behavior, and controller entry points source-compatible.

## Goals

- Centralize pure 3D fisheye transform decisions in a deterministic helper.
- Preserve current runtime behavior for scope ranges, scroll status, lat/lng wrapping, scale clamping, and FOV calculation.
- Add focused unit tests for finite and non-finite values, clamp boundaries, tilt-specific ranges, and scroll status detection.
- Keep `IRGLTransformController3DFisheye` responsible for side effects: matrix mutation, delegate calls, scope mutation, and vertex updates.

## Non-Goals

- Do not rewrite Metal render paths.
- Do not change public render mode APIs or controller method signatures.
- Do not change gesture semantics beyond routing existing decisions through a helper.
- Do not modify VR-specific range behavior in this slice.
- Do not make `swift test` the acceptance gate.

## Architecture

Add `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/Transform/IRGLFisheyeTransformPolicy.swift` as an internal helper.

The helper exposes pure value decisions:

- `scopeRange(for:) -> IRGLScopeRange`
  - Preserves the existing tilt-specific ranges for `.up`, `.toward`, `.backward`, and default.
- `normalizedScope(lat:lng:fov:range:) -> NormalizedScope`
  - Preserves current lat wrapping into `(-90, 90]`, lat clamp to `minLat...(maxLat - fov / 2)`, lng wrapping into `(-180, 180]`, and lng clamp to `minLng...maxLng`.
- `scrollDecision(currentLat:currentLng:dx:dy:friction:range:) -> ScrollDecision?`
  - Returns nil for non-finite deltas.
  - Preserves current delta application and pre-normalization boundary status detection.
- `scaleDecision(requestedScale:maxScale:tanbase:) -> ScaleDecision?`
  - Returns nil for invalid/non-finite scales.
  - Preserves current scale clamp to `1...maxScale` and FOV calculation.
- `aspectRatio(width:height:) -> Float`
  - Preserves `1.0` fallback for invalid sizes.

## Integration Points

- `IRGLTransformController3DFisheye.getScopeRange(of:)` delegates to `IRGLFisheyeTransformPolicy.scopeRange(for:)`.
- `IRGLTransformController3DFisheye.aspectRatio(width:height:)` delegates to policy.
- `updateBy(fx:fy:sx:sy:renew:)` delegates scale/FOV decisions, then mutates matrices as it does today.
- `scroll(dx:dy:)` delegates delta application and status detection, then preserves delegate decisions and side effects.
- `updateVertices()` delegates lat/lng normalization, then preserves camera and view matrix updates.

## Testing

Add `IRGLFisheyeTransformPolicyTests` covering:

- Tilt-specific scope ranges.
- Aspect ratio fallback and finite ratio calculation.
- Scale decision rejects invalid inputs and clamps values to the current behavior.
- Scale decision computes FOV from `tanbase` and scale.
- Scroll decision rejects non-finite deltas.
- Scroll decision applies friction and reports max/min bounds.
- Normalized scope wraps and clamps latitude and longitude.

Keep existing `IRGLTransformController3DFisheyeTests` as integration coverage for controller behavior.

## Acceptance Criteria

- New policy tests fail before implementation because `IRGLFisheyeTransformPolicy` does not exist.
- Focused policy tests pass after helper implementation.
- Existing `IRGLTransformController3DFisheyeTests` pass after controller integration.
- Full iOS simulator suite passes:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3'
```

