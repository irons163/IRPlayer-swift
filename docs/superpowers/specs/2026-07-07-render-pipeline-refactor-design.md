# Render Pipeline Refactor Design

## Summary

This first refactor slice starts the post-2.0 modernization by reducing `IRGLView` render-path responsibility without changing public APIs, playback behavior, Metal shader semantics, or decoder timing.

`IRGLView` remains the display facade for initialization, layout, viewport updates, mode selection, gestures, snapshots, and `IRFFDecoderVideoOutput`. Internal render orchestration moves behind smaller collaborators that can own mode-specific Metal state and dispatch decisions.

The goal is not to make rendering different. The goal is to make the current 2D, VR, fisheye, fish2pano, distortion, and multi4P render paths easier to reason about, test, and optimize in later slices.

## Goals

- Preserve source compatibility for existing public and internal entry points that callers use today.
- Keep all render mode behavior equivalent for 2D, VR, fisheye, fish2pano, distortion, and multi4P.
- Reduce `IRGLView.swift` responsibility by extracting render orchestration and mode-specific Metal state into internal collaborators.
- Keep `IRGLRenderInternal` as the primary render test seam.
- Make mode-specific state reset, setup, and render dispatch easier to test without requiring real playback.
- Keep the current render queue model and avoid introducing new main-thread blocking in hot render paths.
- Add or update focused tests before production refactor steps whenever behavior is being pinned.

## Non-Goals

- Do not change public render mode APIs, player APIs, or decoder APIs.
- Do not rewrite `IRMetalRenderer`, Metal shaders, pixel format conversion, or mesh generation in this slice.
- Do not change FFmpeg, AVPlayer, audio, buffering, seek, or frame delivery behavior.
- Do not change gesture semantics, viewport math, snapshot behavior, or content mode behavior.
- Do not remove existing render modes or collapse mode-specific rendering into a single generic path.
- Do not use `swift test` as the acceptance gate for iOS-only behavior.

## Current Context

`IRGLView.swift` currently owns several responsibilities at once:

- Metal layer, device, command queue, CI context, and fallback image rendering.
- Current frame/image state and snapshot triggering.
- Mode setup and render strategy attachment.
- Viewport, content mode, scroll, pinch, and fallback fisheye controller updates.
- Fisheye, VR, fish2pano, and distortion Metal cache state.
- Render dispatch through `renderCurrentContent` and `renderMetal*IfNeeded` helpers.

The existing test surface is already useful for a behavior-preserving refactor:

- `IRGLViewSnapshotTests` covers selected-mode dispatch for 2D, multi4P, fisheye, VR, distortion, and fish2pano.
- `IRGLRenderStrategyFactoryTests` covers strategy classification and forwarding.
- `IRMetalRendererPixelFormatTests` and `IRMetalRendererDistortionTests` cover lower-level Metal renderer behavior.

This slice should use those tests as guardrails while adding focused coverage for any newly extracted internal units.

## Architecture

Add internal-only collaborators under `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/`:

- `IRGLViewRenderCoordinator`
- `IRGLViewRenderState`
- Small value/context types only where they make dependencies explicit.

`IRGLView` remains the owner of UIKit-facing concerns and the render queue. It passes queue-confined state to the coordinator while preserving current call order and fallback behavior.

The coordinator is responsible for the current `renderCurrentContent` decision flow:

1. Validate Metal layer and drawable size.
2. Try mode-specific Metal rendering in the current precedence order:
   - multi4P
   - fish2pano
   - distortion
   - fisheye
   - VR
   - regular 2D render
3. Preserve the existing early-return behavior after successful Metal rendering.
4. Preserve unsupported YUV-frame behavior.
5. Fall back to `CIImage` rendering for supported image fallback frames.
6. Trigger snapshot saving after a completed render, as today.

`IRGLViewRenderState` is responsible for mode-specific cached resources:

- Fisheye mesh, VR mesh, fisheye controller, fisheye parameter, and last fisheye mesh size.
- Fish2pano shader params, lookup textures, last output size, and antialias count.
- Distortion left/right meshes.

State reset must remain explicit and must be called from the same lifecycle points that currently clear the state.

## Component Boundaries

### `IRGLView`

Keeps:

- `UIView` lifecycle and `layerClass`.
- Metal layer setup, drawable size updates, device/queue/context ownership.
- Public and internal view entry points such as `render`, `clearCanvas`, `choose`, `resetAllViewport`, `updateScope`, `scroll`, and snapshot methods.
- Existing render queue ownership.
- Public render mode storage and selected mode storage.

Delegates:

- Current-frame render dispatch to `IRGLViewRenderCoordinator`.
- Mode-specific setup and reset of Metal render cache state to `IRGLViewRenderState`.

### `IRGLViewRenderCoordinator`

Owns:

- Render dispatch ordering.
- Calls into `IRGLRenderInternal`.
- CI fallback render command encoding, using dependencies supplied by `IRGLView`.
- Snapshot completion notification back to `IRGLView` through a small closure or method callback.

Does not own:

- UIKit view lifecycle.
- Mode arrays or mode registration.
- Metal device creation.
- The render queue itself.

### `IRGLViewRenderState`

Owns:

- Render-mode cache reset and setup.
- Lazy creation and reuse of fisheye, VR, fish2pano, and distortion resources.
- Texture upload helpers that depend on the current `MTLDevice`.

Does not own:

- The selected render mode.
- `CAMetalLayer`.
- `IRMetalRenderer` pipelines.
- Player or decoder state.

## Data Flow

`IRGLView.render(_:)` remains the queue-confined entry point. When a new frame arrives, `IRGLView` updates `lastFrameWidth`, `lastFrameHeight`, `currentFrame`, and `currentImage` as it does today. It then calls the coordinator with a render context containing:

- The current Metal layer.
- Current frame and fallback image.
- Selected mode.
- Fallback renderer.
- Render content mode.
- Device, command queue, CI context, and color space.
- Access to `IRGLViewRenderState`.

The coordinator returns an internal render result with explicit outcomes:

- Completed render, so snapshot completion should be considered.
- No render occurred.
- Fallback image was prepared or retained for future CI rendering.

The result type can be an enum or a small value type, but it must carry those outcomes explicitly and must not leak UIKit lifecycle ownership into the coordinator.

## Threading

The render queue remains owned by `IRGLView`. Extracted collaborators must be used from the same queue-confined paths unless a helper is explicitly pure and thread-safe.

The current deadlock-avoidance behavior around main-thread state capture in `initGL(with:)` must remain intact. The refactor must not add `DispatchQueue.main.sync` calls from inside the render queue.

## Error Handling

Invalid or unavailable render resources continue to behave as today:

- Invalid drawable size exits without rendering.
- Missing mode-specific resources return `false` for that mode-specific render path.
- Fish2pano clears the drawable while lookup textures are not ready, then treats the clear as a completed render.
- Unsupported YUV frames do not fall through to CI image rendering.
- CI fallback exits when no fallback image, command queue, command buffer, or CI context is available.

The new collaborators should avoid throwing. Existing guard-based early exits should be preserved.

## Testing

Add or update focused tests before each behavior-affecting extraction:

- Keep `IRGLViewSnapshotTests` proving mode dispatch for 2D, multi4P, fisheye, VR, distortion, and fish2pano.
- Add focused tests for any new pure or mostly-pure state helpers, especially fish2pano texture readiness, cache invalidation, and mode setup reset behavior.
- Keep `IRGLRenderStrategyFactoryTests` proving strategy selection and forwarding.
- Keep lower-level `IRMetalRendererPixelFormatTests` and `IRMetalRendererDistortionTests` as renderer behavior guards.
- Run focused render tests before the full simulator suite.

Use XcodeBuildMCP session defaults for focused simulator runs with these test targets:

- `IRPlayer-swiftTests/IRGLViewSnapshotTests`
- `IRPlayer-swiftTests/IRGLRenderStrategyFactoryTests`
- `IRPlayer-swiftTests/IRMetalRendererPixelFormatTests`
- `IRPlayer-swiftTests/IRMetalRendererDistortionTests`

Full acceptance should use the configured local iOS simulator through XcodeBuildMCP or an equivalent `xcodebuild test` destination selected from the local `xcodebuild -list` and simulator inventory.

## Acceptance Criteria

- No public API signatures are changed.
- 2D, VR, fisheye, fish2pano, distortion, and multi4P selected-mode dispatch remains behaviorally equivalent.
- `IRGLView.swift` no longer directly owns all mode-specific Metal cache state and render dispatch helpers.
- Extracted collaborators are internal-only and have focused coverage where their behavior can be tested without real playback.
- Focused render tests pass.
- Full iOS simulator suite passes.
- `git diff --check` passes.

## Implementation Boundary

This slice may edit:

- `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift`
- New internal RenderKit files for the coordinator and state.
- Focused tests under `Tests/IRPlayer-swiftTests/`.

This slice should avoid editing:

- `Sources/IRPlayer-swift/Class/Core/FFPlayer/`
- `Sources/IRPlayer-swift/Class/Core/AVPlayer/`
- `Sources/IRPlayer-swift/Class/Core/Audio/`
- Metal shader source files, unless a test reveals an existing issue unrelated to this refactor and the user approves a separate fix.

## Future Phases

Later refactor phases can build on this split:

- Move more renderer policy decisions out of `IRMetalRenderer` if duplication remains after this slice.
- Tighten mode/program boundaries once `IRGLView` no longer owns mode-specific render cache details.
- Review FFmpeg decoder orchestration as a separate slice after display rendering has a clearer internal boundary.
