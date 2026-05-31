# AGENTS.md — RenderKit

High-level rendering abstraction layer that sits above the Metal renderer.

## Top-Level Files

| File                        | Purpose                                          |
|-----------------------------|--------------------------------------------------|
| `IRGLView.swift`            | Main display view — hosts Metal rendering surface |
| `IRGLMath.swift`            | Math utilities for rendering calculations        |
| `IRGLRenderAdapters.swift`  | Render adapter protocols/bridges                 |
| `IRGLSupportPixelFormat.swift` | Pixel format support declarations             |

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

1. `IRGLView` selects an `IRGLRenderMode`
2. The mode configures an `IRGLProgram` via its `Factory`
3. The program sets up `Projection` + `Transform` + `Scope`
4. On each frame, the program feeds uniforms to `IRMetalRenderer`

## Agent Notes

- `IRGLView` is the primary public-facing display component.
- Mode selection drives which program, projection, and transform are used.
- Each render mode has a corresponding factory in `Program/Factory/`.
- Shader params in `Params/` are consumed by programs to set uniforms.
- When adding a new render mode, you need: a Mode, a Program, a Factory, and potentially a new Transform/Projection.
