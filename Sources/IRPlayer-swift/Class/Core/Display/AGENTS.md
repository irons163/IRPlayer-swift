# AGENTS.md — Display

The rendering and display subsystem — the largest part of the framework.

## Subdirectories

| Directory     | Purpose                                                        |
|---------------|----------------------------------------------------------------|
| `Metal/`      | Metal GPU renderer — shaders, mesh generation, pixel rendering |
| `RenderKit/`  | High-level render abstraction — modes, programs, projections, transforms, scopes |

## Architecture

```
IRGLView (RenderKit)
  └── IRGLRenderMode (selects rendering strategy)
       └── IRGLProgram (configures projection + transform)
            └── IRMetalRenderer (Metal GPU rendering)
                 └── IRMetalShaders.metal (GPU shader code)
```

## Agent Notes

- `Metal/` handles low-level GPU rendering. `RenderKit/` handles the logical rendering pipeline.
- All rendering goes through Metal (compile flag `IR_USE_METAL`). There is no OpenGL path.
- Frame timing and threading are critical — do not block the main thread in render paths.
- When modifying rendering, test all affected modes: 2D, VR, fisheye, fish2pano, distortion, multi4P.
