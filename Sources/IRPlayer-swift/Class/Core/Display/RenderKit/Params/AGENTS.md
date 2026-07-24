# AGENTS.md — Params

Shader parameter containers for fisheye and perspective corrections.

## Files

| File                                | Purpose                                         |
|-------------------------------------|-------------------------------------------------|
| `IRGLFish2PanoPixelMapGeneration.swift` | Immutable managed fish2pano lookup maps     |
| `IRGLShaderParams.swift`            | Base shader parameters protocol/class           |
| `IRGLFish2PanoShaderParams.swift`   | Fisheye-to-panorama shader parameters           |
| `IRGLFish2PerspShaderParams.swift`  | Fisheye-to-perspective shader parameters        |

## Agent Notes

- These params are passed as uniforms to the Metal shader via the program.
- Fish2Pano and Fish2Persp params depend on `IRFisheyeParameter` from `Config/`.
- Fish2pano lookup bytes must remain inside
  `IRGLFish2PanoPixelMapGeneration` and may be read only through its scoped
  immutable buffer operation. Do not reintroduce pointer consume/release
  pairing.
- Publish lookup maps only after every AA texture is complete, and carry
  output geometry and antialias metadata in the same generation.
- Tests: `IRGLShaderParamsTests.swift`,
  `IRGLFish2PanoPixelMapGenerationTests.swift`, and
  `IRGLProgram2DFisheye2PanoTests.swift`.
