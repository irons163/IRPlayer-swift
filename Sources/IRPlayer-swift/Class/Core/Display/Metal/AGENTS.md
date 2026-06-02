# AGENTS.md — Metal

Low-level Metal GPU rendering implementation.

## Files

| File                                        | Purpose                                       |
|---------------------------------------------|-----------------------------------------------|
| `IRMetalRenderer.swift`                     | Core Metal renderer — device, command queue, pipeline setup |
| `IRMetalRenderer+Render2D.swift`            | 2D flat rendering extension                   |
| `IRMetalRenderer+RenderDistortion.swift`    | Barrel/pincushion distortion rendering        |
| `IRMetalRenderer+RenderFish2Pano.swift`     | Fisheye-to-panorama projection rendering      |
| `IRMetalRenderer+RenderFisheye.swift`       | 3D fisheye sphere rendering                   |
| `IRMetalRenderer+RenderMesh.swift`          | Generic mesh-based rendering                  |
| `IRMetalRenderer+RenderPixelFormat.swift`   | Pixel format handling (NV12, YUV, RGB)        |
| `IRMetalPixelRenderer.swift`                | Per-pixel Metal rendering utilities           |
| `IRMetalDistortionMesh.swift`               | Distortion correction mesh geometry           |
| `IRMetalFisheyeMesh.swift`                  | Fisheye sphere mesh geometry                  |
| `IRMetalShaders.metal`                      | MSL shader source (vertex + fragment shaders) |

## Agent Notes

- `IRMetalShaders.metal` is compiled as a Metal shader resource — it's a `.process()` SPM resource.
- Renderer extensions map 1:1 to rendering modes — each mode has its own render path.
- Mesh files generate vertex/index buffers for non-planar projections.
- Verify drawable size assumptions and texture layout when editing.
- Pixel format handling must support NV12 (hardware decode), YUV420P (software decode), and RGB.
- Tests: `IRGLViewSnapshotTests.swift` (visual), plus per-program tests in `Tests/`.
