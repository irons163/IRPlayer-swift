# AGENTS.md — Projection

Projection matrix implementations for different rendering modes.

## Files

| File                                   | Purpose                                     |
|----------------------------------------|---------------------------------------------|
| `IRGLProjection.swift`                 | Base projection protocol/class              |
| `IRGLProjectionMesh.swift`             | Immutable mesh values, validation, and pure builders |
| `IRGLProjectionEquirectangular.swift`  | Equirectangular projection (panorama/360°)  |
| `IRGLProjectionOrthographic.swift`     | Orthographic projection (flat 2D)           |
| `IRGLProjectionVR.swift`              | VR stereoscopic projection (dual viewports) |

## Agent Notes

- Projections are consumed by programs to set the projection matrix uniform.
- VR projection handles dual-eye rendering with appropriate inter-pupillary offset.
- Keep projection mesh generations immutable and complete before publication.
- VR mesh state is process-wide immutable data; do not add mutable static
  buffers or lazy setup flags.
- Equirectangular updates build locally and atomically replace the current mesh;
  do not expose partially built vertex, texture, or index storage.
- Preserve vertex counts, winding, UV orientation, and UInt16 index admission
  when changing tessellation.
