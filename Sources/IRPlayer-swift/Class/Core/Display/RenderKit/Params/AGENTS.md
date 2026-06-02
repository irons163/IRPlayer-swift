# AGENTS.md — Params

Shader parameter containers for fisheye and perspective corrections.

## Files

| File                                | Purpose                                         |
|-------------------------------------|-------------------------------------------------|
| `IRGLShaderParams.swift`            | Base shader parameters protocol/class           |
| `IRGLFish2PanoShaderParams.swift`   | Fisheye-to-panorama shader parameters           |
| `IRGLFish2PerspShaderParams.swift`  | Fisheye-to-perspective shader parameters        |

## Agent Notes

- These params are passed as uniforms to the Metal shader via the program.
- Fish2Pano and Fish2Persp params depend on `IRFisheyeParameter` from `Config/`.
- Tests: `IRGLShaderParamsTests.swift`.
