# AGENTS.md — Mode

Render mode definitions that configure the rendering strategy.

## Files

| File                                   | Purpose                                   |
|----------------------------------------|-------------------------------------------|
| `IRGLRenderMode.swift`                 | Base render mode protocol/class           |
| `IRGLRenderMode2D.swift`              | Standard 2D flat video rendering          |
| `IRGLRenderMode2DFisheye2Pano.swift`  | Fisheye-to-panorama unwrapping mode       |
| `IRGLRenderMode3DFisheye.swift`       | 3D fisheye sphere rendering mode          |
| `IRGLRenderModeDistortion.swift`      | Barrel/pincushion distortion correction   |
| `IRGLRenderModeMulti4P.swift`         | Multi-view 4-panel fisheye rendering      |
| `IRGLRenderModeVR.swift`              | Stereoscopic VR rendering mode            |
| `IRGLRenderModeFactory.swift`         | Factory for creating render mode instances |

## Agent Notes

- Each mode maps to a specific `IRGLProgram` and `IRGLProgramFactory`.
- Modes are set via `IRPlayerImp.renderModes` property.
- `IRGLRenderModeFactory` directly owns default mode construction and ordering.
- `IRGLRenderMode` queues typed configuration changes; keep metadata-only
  values out of the program mutation queue.
- Do not introduce string-key dispatch or separate mode policy/plan layers.
- Tests: `IRGLRenderModeBuildTests.swift`, `IRGLRenderModeFactoryTests.swift`.
