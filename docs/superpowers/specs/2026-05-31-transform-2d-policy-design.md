# 2D Transform Policy Design

## Summary

This slice extracts render-independent 2D transform decisions from `IRGLTransformController2D` into an internal pure helper. The helper makes scale clamping, offset clamping, scroll bounds, degree-to-pixel units, and viewport resize mapping independently testable.

Existing public APIs, render mode behavior, matrix mutation, and delegate callbacks remain source-compatible.

## Goals

- Centralize pure 2D transform math in `IRGLTransform2DPolicy`.
- Preserve current behavior for update scale/offset calculations, scroll bounds, degree scroll units, and viewport resize mapping.
- Add focused unit tests for finite/invalid inputs, min/max scale behavior, offset clamps, scroll statuses, and zero-size viewport handling.
- Keep `IRGLTransformController2D` responsible for mutating scope, matrices, delegates, and side effects.

## Non-Goals

- Do not change gesture semantics or render mode APIs.
- Do not rewrite Metal/OpenGL rendering.
- Do not make `swift test` the acceptance gate.

## Acceptance

- Policy tests fail before helper implementation.
- Policy tests pass after helper implementation.
- Existing `IRGLTransformController2DTests` pass after integration.
- Full iOS simulator suite passes.

