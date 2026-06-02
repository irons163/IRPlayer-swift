# AGENTS.md — Program

Render programs that configure geometry, projection, and transform for each rendering mode.

## Top-Level Files

| File                                | Purpose                                    |
|-------------------------------------|--------------------------------------------|
| `IRGLProgram2D.swift`               | 2D flat rendering program                  |
| `IRGLProgram2DFisheye2Pano.swift`   | Fisheye-to-panorama unwrapping program     |
| `IRGLProgram2DFisheye2Persp.swift`  | Fisheye-to-perspective correction program  |
| `IRGLProgram3DFisheye.swift`        | 3D fisheye sphere rendering program        |
| `IRGLProgramMulti.swift`            | Base multi-view program                    |
| `IRGLProgramMulti4P.swift`          | 4-panel multi-view program                 |

## Subdirectories

| Directory      | Contents                                              |
|----------------|-------------------------------------------------------|
| `Distortion/`  | `IRGLProgramDistortion.swift/.h` — distortion correction program |
| `Factory/`     | Program factories — one per mode, creating configured program instances |
| `VR/`          | `IRGLProgramVR.swift/.h` — VR stereoscopic program   |

## Factory Files (`Factory/`)

| File                                    | Creates                         |
|-----------------------------------------|---------------------------------|
| `IRGLProgramFactory.swift`              | Base factory protocol           |
| `IRGLProgram2DFactory.swift`            | 2D program instances            |
| `IRGLProgram2DFisheye2PanoFactory.swift` | Fisheye2Pano program instances |
| `IRGLProgram3DFisheyeFactory.swift`     | 3D fisheye program instances   |
| `IRGLProgram3DFisheye4PFactory.swift`   | 4-panel fisheye instances      |
| `IRGLProgramDistortionFactory.swift`    | Distortion program instances   |
| `IRGLProgramVRFactory.swift`            | VR program instances           |

## Agent Notes

- Programs are the core abstraction — they wire together projection, transform, scope, and shader params.
- `Distortion/` and `VR/` have `.h` headers because they bridge to Objective-C for legacy compatibility.
- Each factory corresponds to a render mode in `Mode/`.
- Tests: `IRGLProgram2DTests.swift`, `IRGLProgram2DFisheye2PanoTests.swift`, `IRGLProgram2DFisheye2PerspTests.swift`, `IRGLProgramDistortionTests.swift`, `IRGLProgramMulti4PTests.swift`, `IRGLProgramFactoryTests.swift`.
