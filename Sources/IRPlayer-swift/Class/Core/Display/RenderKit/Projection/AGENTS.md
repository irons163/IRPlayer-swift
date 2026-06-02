# AGENTS.md — Projection

Projection matrix implementations for different rendering modes.

## Files

| File                                   | Purpose                                     |
|----------------------------------------|---------------------------------------------|
| `IRGLProjection.swift`                 | Base projection protocol/class              |
| `IRGLProjectionEquirectangular.swift`  | Equirectangular projection (panorama/360°)  |
| `IRGLProjectionOrthographic.swift`     | Orthographic projection (flat 2D)           |
| `IRGLProjectionVR.swift`              | VR stereoscopic projection (dual viewports) |

## Agent Notes

- Projections are consumed by programs to set the projection matrix uniform.
- VR projection handles dual-eye rendering with appropriate inter-pupillary offset.
