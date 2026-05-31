# Player Lifecycle Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `IRPlayerImp` lifecycle decisions into a pure internal policy helper with focused tests while preserving public API and runtime behavior.

**Architecture:** Add `IRPlayerLifecyclePolicy.swift` as a small internal value-decision helper. `IRPlayerImp` will keep owning UIKit side effects, lazy backend creation, and concrete AV/FFmpeg calls, but will ask the policy which command, replacement, background, or foreground action to take.

**Tech Stack:** Swift, XCTest, Xcode project test target, iOS Simulator `xcodebuild test`.

---

## File Structure

- Create: `Sources/IRPlayer-swift/Class/IRPlayerLifecyclePolicy.swift`
  - Defines internal policy enums and pure static functions.
  - Imports Foundation only.
- Modify: `Sources/IRPlayer-swift/Class/IRPlayerImp.swift`
  - Replaces lifecycle `switch` decision logic with calls to `IRPlayerLifecyclePolicy`.
  - Keeps public API, UIKit side effects, lazy player ownership, and backend calls in place.
- Create: `Tests/IRPlayer-swiftTests/IRPlayerLifecyclePolicyTests.swift`
  - Tests pure policy decisions without playback, rendering, UIKit notifications, AVPlayer, or FFmpeg.
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`
  - Adds the new production source file to the framework target.
  - Adds the new test file to the test target.

## Task 1: Add Failing Lifecycle Policy Tests

**Files:**
- Create: `Tests/IRPlayer-swiftTests/IRPlayerLifecyclePolicyTests.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests**

Create `Tests/IRPlayer-swiftTests/IRPlayerLifecyclePolicyTests.swift`:

```swift
import XCTest
@testable import IRPlayer_swift

final class IRPlayerLifecyclePolicyTests: XCTestCase {

    func testCommandTargetFollowsDecoderType() {
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: .avPlayer), .avPlayer)
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: .ffmpeg), .ffmpeg)
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: .error), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: .none), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: nil), .none)
    }

    func testReplacementPlanStopsOppositeBackendAndSelectsReplacementTarget() {
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: .avPlayer, hasAVPlayer: false, hasFFPlayer: true),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: false, stopFFPlayer: true, replaceTarget: .avPlayer)
        )

        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: .ffmpeg, hasAVPlayer: true, hasFFPlayer: false),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: true, stopFFPlayer: false, replaceTarget: .ffmpeg)
        )
    }

    func testReplacementPlanStopsExistingBackendsForInvalidDecoderTargets() {
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: .error, hasAVPlayer: true, hasFFPlayer: true),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: true, stopFFPlayer: true, replaceTarget: .none)
        )

        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: .none, hasAVPlayer: true, hasFFPlayer: true),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: true, stopFFPlayer: true, replaceTarget: .none)
        )

        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: nil, hasAVPlayer: true, hasFFPlayer: false),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: true, stopFFPlayer: false, replaceTarget: .none)
        )
    }

    func testBackgroundActionAutoPausesOnlyActivePlaybackStates() {
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .playing), .pauseAndRememberAutoPlay)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .buffering), .pauseAndRememberAutoPlay)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .readyToPlay), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .suspend), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .failed), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .nothing, state: .playing), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .continuing, state: .buffering), .none)
    }

    func testForegroundActionAutoResumesOnlySuspendedRememberedPlayback() {
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.foregroundAction(mode: .autoPlayAndPause, state: .suspend, needAutoPlay: true),
            .playAndClearAutoPlay
        )
        XCTAssertEqual(IRPlayerLifecyclePolicy.foregroundAction(mode: .autoPlayAndPause, state: .suspend, needAutoPlay: false), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.foregroundAction(mode: .autoPlayAndPause, state: .playing, needAutoPlay: true), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.foregroundAction(mode: .nothing, state: .suspend, needAutoPlay: true), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.foregroundAction(mode: .continuing, state: .suspend, needAutoPlay: true), .none)
    }
}
```

- [ ] **Step 2: Add the test file to the Xcode test target**

Edit `IRPlayer-swift.xcodeproj/project.pbxproj` using the existing test-file patterns:

- Add a `PBXFileReference` for `IRPlayerLifecyclePolicyTests.swift`.
- Add a `PBXBuildFile` for `IRPlayerLifecyclePolicyTests.swift in Sources`.
- Add the file reference under the `IRPlayer-swiftTests` group.
- Add the build file under the `IRPlayer-swiftTests` target `PBXSourcesBuildPhase`.

- [ ] **Step 3: Run the focused test to verify RED**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3' -only-testing:IRPlayer-swiftTests/IRPlayerLifecyclePolicyTests
```

Expected: FAIL because `IRPlayerLifecyclePolicy` does not exist.

- [ ] **Step 4: Commit the red test**

```sh
git add Tests/IRPlayer-swiftTests/IRPlayerLifecyclePolicyTests.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "test: cover player lifecycle policy decisions"
```

## Task 2: Implement the Pure Lifecycle Policy

**Files:**
- Create: `Sources/IRPlayer-swift/Class/IRPlayerLifecyclePolicy.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the minimal policy implementation**

Create `Sources/IRPlayer-swift/Class/IRPlayerLifecyclePolicy.swift`:

```swift
import Foundation

enum IRPlayerLifecyclePolicy {
    enum BackendTarget: Equatable {
        case none
        case avPlayer
        case ffmpeg
    }

    struct ReplacementPlan: Equatable {
        let stopAVPlayer: Bool
        let stopFFPlayer: Bool
        let replaceTarget: BackendTarget
    }

    enum BackgroundAction: Equatable {
        case none
        case pauseAndRememberAutoPlay
    }

    enum ForegroundAction: Equatable {
        case none
        case playAndClearAutoPlay
    }

    static func commandTarget(for decoderType: IRDecoderType?) -> BackendTarget {
        switch decoderType {
        case .avPlayer:
            return .avPlayer
        case .ffmpeg:
            return .ffmpeg
        case .error, .none:
            return .none
        }
    }

    static func replacementPlan(for decoderType: IRDecoderType?, hasAVPlayer: Bool, hasFFPlayer: Bool) -> ReplacementPlan {
        switch decoderType {
        case .avPlayer:
            return ReplacementPlan(stopAVPlayer: false, stopFFPlayer: hasFFPlayer, replaceTarget: .avPlayer)
        case .ffmpeg:
            return ReplacementPlan(stopAVPlayer: hasAVPlayer, stopFFPlayer: false, replaceTarget: .ffmpeg)
        case .error, .none:
            return ReplacementPlan(stopAVPlayer: hasAVPlayer, stopFFPlayer: hasFFPlayer, replaceTarget: .none)
        }
    }

    static func backgroundAction(mode: IRPlayerBackgroundMode, state: IRPlayerState) -> BackgroundAction {
        guard mode == .autoPlayAndPause else { return .none }
        switch state {
        case .playing, .buffering:
            return .pauseAndRememberAutoPlay
        default:
            return .none
        }
    }

    static func foregroundAction(mode: IRPlayerBackgroundMode, state: IRPlayerState, needAutoPlay: Bool?) -> ForegroundAction {
        guard mode == .autoPlayAndPause else { return .none }
        guard state == .suspend, needAutoPlay == true else { return .none }
        return .playAndClearAutoPlay
    }
}
```

- [ ] **Step 2: Add the production file to the Xcode framework target**

Edit `IRPlayer-swift.xcodeproj/project.pbxproj` using the existing source-file patterns:

- Add a `PBXFileReference` for `IRPlayerLifecyclePolicy.swift`.
- Add a `PBXBuildFile` for `IRPlayerLifecyclePolicy.swift in Sources`.
- Add the file reference under the main source group near `IRPlayerImp.swift`.
- Add the build file under the `IRPlayer-swift` target `PBXSourcesBuildPhase`.

- [ ] **Step 3: Run the focused policy tests to verify GREEN**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3' -only-testing:IRPlayer-swiftTests/IRPlayerLifecyclePolicyTests
```

Expected: PASS for `IRPlayerLifecyclePolicyTests`.

- [ ] **Step 4: Commit the policy helper**

```sh
git add Sources/IRPlayer-swift/Class/IRPlayerLifecyclePolicy.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "feat: add player lifecycle policy helper"
```

## Task 3: Route IRPlayerImp Through the Policy

**Files:**
- Modify: `Sources/IRPlayer-swift/Class/IRPlayerImp.swift`

- [ ] **Step 1: Refactor `play` and `pause` to use `commandTarget`**

Replace only the decoder switch in `play()` and `pause()` with:

```swift
switch IRPlayerLifecyclePolicy.commandTarget(for: self.decoderType) {
case .avPlayer:
    self.avPlayer.play()
case .ffmpeg:
    self.ffPlayer.play()
case .none:
    break
}
```

and:

```swift
switch IRPlayerLifecyclePolicy.commandTarget(for: self.decoderType) {
case .avPlayer:
    self.avPlayer.pause()
case .ffmpeg:
    self.ffPlayer.pause()
case .none:
    break
}
```

Keep the existing idle timer side effects unchanged.

- [ ] **Step 2: Refactor `replaceVideoWithURL` to use `replacementPlan`**

After assigning `self.decoderType` and `self.videoType`, create:

```swift
let replacementPlan = IRPlayerLifecyclePolicy.replacementPlan(
    for: self.decoderType,
    hasAVPlayer: self._avPlayer != nil,
    hasFFPlayer: self._ffPlayer != nil
)
```

Then replace the current `switch self.decoderType` body with:

```swift
if replacementPlan.stopAVPlayer {
    self.avPlayer.stop()
}
if replacementPlan.stopFFPlayer {
    self.ffPlayer.stop()
}

switch replacementPlan.replaceTarget {
case .avPlayer:
    self.avPlayer.replaceVideo()
case .ffmpeg:
    self.ffPlayer.replaceVideo()
    if self.videoInput?.outputType == .decoder {
        self.videoInput?.videoOutput = self.ffPlayer.decoder
    }
case .none:
    break
}
```

Do not move the existing `videoInput.videoOutput = self.displayView` assignment before the policy call.

- [ ] **Step 3: Refactor background and foreground handlers**

In `applicationDidEnterBackground`, replace the nested switches with:

```swift
switch IRPlayerLifecyclePolicy.backgroundAction(mode: self.backgroundMode, state: self.state) {
case .pauseAndRememberAutoPlay:
    self.needAutoPlay = true
    self.pause()
case .none:
    break
}
```

In `applicationWillEnterForeground`, replace the nested switches with:

```swift
switch IRPlayerLifecyclePolicy.foregroundAction(mode: self.backgroundMode, state: self.state, needAutoPlay: self.needAutoPlay) {
case .playAndClearAutoPlay:
    self.needAutoPlay = false
    self.play()
    self.lastForegroundTimeInterval = NSDate().timeIntervalSince1970
case .none:
    break
}
```

- [ ] **Step 4: Run focused tests**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3' -only-testing:IRPlayer-swiftTests/IRPlayerLifecyclePolicyTests -only-testing:IRPlayer-swiftTests/IRPlayerImpLazyPlayerTests
```

Expected: PASS.

- [ ] **Step 5: Commit the `IRPlayerImp` refactor**

```sh
git add Sources/IRPlayer-swift/Class/IRPlayerImp.swift
git commit -m "refactor: route player lifecycle decisions through policy"
```

## Task 4: Full Verification

**Files:**
- No production changes.

- [ ] **Step 1: Run whitespace and project sanity checks**

Run:

```sh
git diff --check
git status --short
```

Expected: no whitespace errors; status is clean after the Task 3 commit.

- [ ] **Step 2: Run the full iOS simulator test suite**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3'
```

Expected: all tests pass, including the existing 277 tests plus the new lifecycle policy tests.

- [ ] **Step 3: Report final status**

Include:

- Commit hashes created by this plan.
- Full test result summary.
- Note that public API signatures in `IRPlayerImp` were preserved.
