# AGENTS.md — Matrix

Sensor and motion utilities.

## Files

- `IRSensor.swift` — Lifecycle facade, main-thread delivery, and synchronized
  weak viewport targets.
- `IRSensorMotionDriver.swift` — Core Motion adapter and immutable motion
  values.
- `IRSensorMotionSession.swift` — Locked generation, reference quaternion,
  orientation, offset state, and motion math.

## Agent Notes

- Used by VR mode and device shift controllers for gyroscope-based view rotation.
- Core Motion objects must remain inside `IRSystemSensorMotionDriver`; publish
  immutable `IRSensorMotionSample` values to the rest of the framework.
- Keep callback processing and main-thread delivery fenced by both motion
  generation and orientation.
- Restart and stop must revoke the session generation before stopping or
  replacing driver work.
- Reference quaternion, orientation, and accumulated offsets belong to
  `IRSensorMotionSession` and must stay under its lock.
- Do not reintroduce mutable `CMAttitude` state or per-callback captured
  offsets.
- Tests: `IRMatrix4Tests.swift`, `IRSensorMotionDriverTests.swift`,
  `IRSensorMotionSessionTests.swift`, and `IRSensorTests.swift`.
