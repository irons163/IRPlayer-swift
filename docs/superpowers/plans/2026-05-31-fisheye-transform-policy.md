# Fisheye Transform Policy Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans or implement task-by-task locally. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract render-independent 3D fisheye transform decisions into a pure internal policy helper and cover them with unit tests.

**Architecture:** Add `IRGLFisheyeTransformPolicy.swift` as an internal helper under the RenderKit transform folder. Existing controller code keeps side effects and public entry points, but delegates pure decisions to the helper.

**Tech Stack:** Swift, XCTest, Xcode project test target, iOS Simulator `xcodebuild test`.

---

## File Structure

- Create: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/Transform/IRGLFisheyeTransformPolicy.swift`
- Modify: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/Transform/IRGLTransformController3DFisheye.swift`
- Create: `Tests/IRPlayer-swiftTests/IRGLFisheyeTransformPolicyTests.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

## Task 1: Add Failing Policy Tests

- [ ] Add `IRGLFisheyeTransformPolicyTests` for scope ranges, aspect ratio, scale/FOV decisions, scroll decisions, and normalized scope.
- [ ] Add the test file to the Xcode test target.
- [ ] Run focused tests and confirm RED because `IRGLFisheyeTransformPolicy` does not exist.
- [ ] Commit: `test: cover fisheye transform policy decisions`

## Task 2: Implement Pure Policy Helper

- [ ] Add `IRGLFisheyeTransformPolicy.swift` with small Equatable value structs for `NormalizedScope`, `ScrollDecision`, and `ScaleDecision`.
- [ ] Add the helper to the Xcode framework target.
- [ ] Run focused policy tests and confirm GREEN.
- [ ] Commit: `feat: add fisheye transform policy helper`

## Task 3: Integrate Controller

- [ ] Route `getScopeRange(of:)`, `aspectRatio(width:height:)`, `updateBy`, `scroll(dx:dy:)`, and `updateVertices()` through the policy.
- [ ] Preserve delegate calls, matrix updates, scope mutation, and update timing.
- [ ] Run focused policy plus `IRGLTransformController3DFisheyeTests`.
- [ ] Commit: `refactor: route fisheye transform decisions through policy`

## Task 4: Verify

- [ ] Run `git diff --check`.
- [ ] Run the full iOS simulator suite:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3'
```

- [ ] Review final diff against the spec boundary.

