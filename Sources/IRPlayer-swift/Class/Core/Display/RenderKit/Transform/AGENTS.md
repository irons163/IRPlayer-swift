# AGENTS.md — Transform

Transform controllers that map user input to view matrix changes.

## Files

| File                                       | Purpose                                       |
|--------------------------------------------|-----------------------------------------------|
| `IRGLTransformController.swift`            | Base transform controller protocol/class      |
| `IRGLTransformController2D.swift`          | 2D pan/zoom transform                         |
| `IRGLTransformController3DFisheye.swift`   | 3D fisheye sphere rotation transform          |
| `IRGLTransformControllerDistortion.swift`  | Distortion-specific transform                 |
| `IRGLTransformControllerVR.swift`          | VR head-tracking transform                    |

## Agent Notes

- Transform controllers are set by programs and updated by input controllers (`Controller/`).
- Each transform type handles different coordinate spaces and rotation models.
- Tests: `IRGLTransformController2DTests.swift`, `IRGLTransformController3DFisheyeTests.swift`, `IRGLTransformControllerVRTests.swift`.
