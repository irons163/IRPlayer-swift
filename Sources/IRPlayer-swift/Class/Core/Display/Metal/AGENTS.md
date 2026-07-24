# AGENTS.md — Metal

Low-level Metal GPU rendering implementation.

## Files

| File                                        | Purpose                                       |
|---------------------------------------------|-----------------------------------------------|
| `IRMetalCommandResources.swift`             | Per-command resource cache and GPU-completion lifetime |
| `IRMetalDistortionTargetSession.swift`      | Synchronized coherent distortion render-target generations |
| `IRMetalFrameTextureGeneration.swift`       | Immutable NV12/BGRA/I420/RGB texture generations |
| `IRMetalRenderer.swift`                     | Core Metal renderer — device, command queue, pipeline setup |
| `IRMetalRendererResources.swift`            | Complete immutable cache, pipeline, and quad-buffer bootstrap |
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
- Publish an `IRMetalRenderer` only from one complete
  `IRMetalRendererResources` generation. Texture caches, pipelines, and quad
  buffers are non-optional after bootstrap; test failures through injected
  resource dependencies instead of mutating a live renderer.
- A prepared surface passes its command queue into the renderer. Do not create
  a second queue inside that surface generation.
- Keep distortion target texture and dimensions coherent inside
  `IRMetalDistortionTargetSession`; failed replacements preserve the previous
  complete target and close is terminal.
- Mesh files generate vertex/index buffers for non-planar projections.
- Verify drawable size assumptions and texture layout when editing.
- Pixel format handling must support NV12 (hardware decode), YUV420P (software decode), and RGB.
- Keep every `CVMetalTexture` and its source pixel buffer inside one
  `IRMetalFrameTextureGeneration`; extracting an `MTLTexture` is not an
  ownership transfer.
- Every submitted renderer command must move its `IRMetalCommandResources` to
  a command-buffer completion handler before commit.
- Reuse the command scope's cached generation across multiple viewports or
  distortion eyes; never add a cross-command decoded-frame texture cache.
- Upload software I420 textures from one `IRFFYUVPlaneSnapshot`; never read
  frame width/height separately from plane bytes or retain pointers beyond
  `withUnsafePlaneBytes`.
- Upload custom RGB textures from one `IRRGBFrameSnapshot`. RGB24 uses its
  precomputed RGBA8 bytes and BGRA32 preserves its validated byte order and
  row stride.
- Respect snapshot-provided chroma dimensions, including odd-sized I420 input.
- Tests: `IRMetalCommandResourcesTests.swift`,
  `IRMetalFrameTextureGenerationTests.swift`,
  `IRMetalRendererPixelFormatTests.swift`, `IRGLViewSnapshotTests.swift`
  (visual), plus per-program tests in `Tests/`.
