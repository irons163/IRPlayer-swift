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
- Transform controllers own their pure decision values and calculations; do
  not split them into separate policy types.
- Reject malformed ranges, non-finite inputs, and non-finite intermediate
  values before mutating scope or matrices.
- Re-clamp offsets after viewport resize and normalize fisheye angles with
  constant-work remainder arithmetic.
- Tests: `IRGLTransform2DSemanticsTests.swift`,
  `IRGLFisheyeTransformSemanticsTests.swift`,
  `IRGLTransformController2DTests.swift`,
  `IRGLTransformController3DFisheyeTests.swift`, and
  `IRGLTransformControllerVRTests.swift`.
