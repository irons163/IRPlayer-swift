# AGENTS.md — RenderKit

High-level rendering abstraction layer that sits above the Metal renderer.

## Top-Level Files

| File | Purpose |
|------|---------|
| `IRGLView.swift` | UIKit/API facade over the display runtime owners |
| `IRGLRenderExecutor.swift` | Reentrant-safe serial render execution domain |
| `IRGLMetalSurfaceSession.swift` | Complete Metal surface generations and drawable sizing |
| `IRGLFrameSubmissionSession.swift` | Current frame/image ownership and render completion |
| `IRGLRenderSession.swift` | Aggregate mode, viewport, interaction, surface, and frame lifecycle |
| `IRGLSnapshotSession.swift` | Coalesced snapshot requests and stale-work cancellation |
| `IRGLAVPlayerLayerSession.swift` | Main-thread AVPlayer-layer attachment and teardown |
| `IRGLRenderStrategyFactory.swift` | Render-mode classification and strategy construction |
| `IRGLViewRenderState.swift` | Mode-specific cached Metal resources |
| `IRGLViewRenderCoordinator.swift` | One render attempt over an immutable context |
| `IRGLMath.swift` | Math utilities for rendering calculations |
| `IRGLRenderAdapters.swift` | Render adapter protocols/bridges |
| `IRGLSupportPixelFormat.swift` | Pixel format support declarations |

## Subdirectories

| Directory      | Purpose                                                          |
|----------------|------------------------------------------------------------------|
| `Mode/`        | Render mode definitions (2D, VR, fisheye, panorama, distortion, multi4P) |
| `Params/`      | Shader parameter containers for fisheye/perspective corrections  |
| `Program/`     | Render programs — configure geometry, projection, and transform per mode |
| `Projection/`  | Projection matrix implementations (equirectangular, orthographic, VR) |
| `Scope/`       | 2D/3D scope definitions for viewport bounds                     |
| `Transform/`   | Transform controllers — map user input to view matrix changes   |

## Rendering Pipeline

1. `IRGLView` captures UIKit geometry and translates API calls.
2. `IRGLRenderSession` serializes surface, mode, viewport, and frame work.
3. The selected mode configures an `IRGLProgram` via its factory.
4. `IRGLFrameSubmissionSession` asks `IRGLViewRenderCoordinator` to render the
   owned frame/image through the selected strategy.
5. The program feeds projection, transform, scope, and texture state to
   `IRMetalRenderer`.

## Agent Notes

- `IRGLView` is the primary public-facing display component; do not put raw
  Metal, frame, snapshot, or AVPlayer-layer ownership back into it.
- All mode, viewport, interaction, surface, and frame mutations must enter
  `IRGLRenderSession` and its `IRGLRenderExecutor`.
- Capture UIKit state before entering the render domain. Render-domain work
  must never synchronously request main-thread state.
- Keep surface generations complete-or-unavailable and make close terminal.
- A ready Metal surface owns one command queue shared by its Core Image path
  and `IRMetalRenderer`; propagate typed renderer bootstrap failures without
  publishing partial surface resources.
- Mode selection drives which program, projection, and transform are used.
- Each render mode has a corresponding factory in `Program/Factory/`.
- Shader params in `Params/` are consumed by programs to set uniforms.
- Keep render-domain decisions on their owning mode, program, parameter, or
  transform type. Do not add parallel `*Policy` wrappers that mirror owner
  APIs.
- Validate both external numeric inputs and derived arithmetic before
  publishing viewport, transform, scope, shader, or projection state.
- Angle and panorama wrapping must use bounded-work remainder arithmetic;
  never normalize finite values with magnitude-proportional loops.
- When adding a new render mode, you need: a Mode, a Program, a Factory, and potentially a new Transform/Projection.
