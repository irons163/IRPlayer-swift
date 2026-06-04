# Playback Time and Buffering Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract playback time math, seek clamping, playable clamping, progress-post throttling, and buffering state decisions into a pure internal policy helper.

**Architecture:** Add `IRPlaybackTimePolicy.swift` as an internal pure helper with small value-returning decisions. Existing player and decoder files keep side effects, notifications, delegate calls, and queue control, but delegate value decisions to the policy.

**Tech Stack:** Swift, XCTest, Xcode project test target, iOS Simulator `xcodebuild test`.

---

## File Structure

- Create: `Sources/IRPlayer-swift/Class/IRPlaybackTimePolicy.swift`
  - Defines pure static functions for percent, playable clamping, seek clamping, progress posting, and buffering state.
  - Imports Foundation only.
- Modify: `Sources/IRPlayer-swift/Class/IRPlayerAction.swift`
  - Routes `IRPlayerNotificationPayload.timePercent` through `IRPlaybackTimePolicy.percent`.
- Modify: `Sources/IRPlayer-swift/Class/Core/FFPlayer/IRFFPlayer.swift`
  - Routes playable clamping and progress-post throttling through the policy.
- Modify: `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift`
  - Routes seek clamping and buffering-state decision through the policy.
- Create: `Tests/IRPlayer-swiftTests/IRPlaybackTimePolicyTests.swift`
  - Tests policy behavior without constructing players, decoders, renderers, or FFmpeg loops.
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`
  - Adds `IRPlaybackTimePolicy.swift` to the `IRPlayer-swift` framework target and `IRPlaybackTimePolicyTests.swift` to the `IRPlayer-swiftTests` target.

## Task 1: Add Failing Playback Time Policy Tests

**Files:**
- Create: `Tests/IRPlayer-swiftTests/IRPlaybackTimePolicyTests.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests**

Create `Tests/IRPlayer-swiftTests/IRPlaybackTimePolicyTests.swift`:

```swift
import XCTest
@testable import IRPlayer_swift

final class IRPlaybackTimePolicyTests: XCTestCase {

    func testPercentUsesFinitePositiveTotal() {
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: 3, total: 12), NSNumber(value: 0.25))
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: 3, total: 0), NSNumber(value: 0))
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: 3, total: -1), NSNumber(value: 0))
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: .nan, total: 12), NSNumber(value: 0))
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: 3, total: .infinity), NSNumber(value: 0))
    }

    func testClampedPlayableTimeBoundsFiniteValuesToDuration() {
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(4, duration: 10), 4)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(-1, duration: 10), 0)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(12, duration: 10), 10)
    }

    func testClampedPlayableTimeRejectsInvalidValues() {
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(.nan, duration: 10), 0)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(5, duration: .nan), 0)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(5, duration: -1), 0)
    }

    func testClampedSeekTimeBoundsRequestedTime() {
        XCTAssertEqual(IRPlaybackTimePolicy.clampedSeekTime(requested: 5, min: 1, max: 10), 5)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedSeekTime(requested: -2, min: 1, max: 10), 1)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedSeekTime(requested: 12, min: 1, max: 10), 10)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedSeekTime(requested: 12, min: 4, max: 2), 4)
    }

    func testClampedSeekTimeRejectsNonFiniteInputs() {
        XCTAssertNil(IRPlaybackTimePolicy.clampedSeekTime(requested: .nan, min: 0, max: 10))
        XCTAssertNil(IRPlaybackTimePolicy.clampedSeekTime(requested: 1, min: .infinity, max: 10))
        XCTAssertNil(IRPlaybackTimePolicy.clampedSeekTime(requested: 1, min: 0, max: .nan))
    }

    func testBufferingStateEntersAndExitsBuffering() {
        XCTAssertTrue(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: false, bufferedDuration: 0.2, minBufferedDuration: 2, endOfFile: false))
        XCTAssertFalse(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: false, bufferedDuration: 0.3, minBufferedDuration: 2, endOfFile: false))
        XCTAssertTrue(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: true, bufferedDuration: 1, minBufferedDuration: 2, endOfFile: false))
        XCTAssertFalse(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: true, bufferedDuration: 2, minBufferedDuration: 2, endOfFile: false))
        XCTAssertFalse(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: true, bufferedDuration: 0, minBufferedDuration: 2, endOfFile: true))
    }

    func testBufferingStateTreatsNonFiniteDurationsAsZero() {
        XCTAssertTrue(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: false, bufferedDuration: .nan, minBufferedDuration: 2, endOfFile: false))
        XCTAssertFalse(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: true, bufferedDuration: 1, minBufferedDuration: .nan, endOfFile: false))
    }

    func testProgressPostDecisionPostsAtStartEndAndThrottleBoundary() {
        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 0, oldProgress: 1, duration: 10, lastPostTime: 20, now: 20.1, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: true, current: 0, total: 10, nextLastPostTime: 20)
        )

        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 10, oldProgress: 9, duration: 10, lastPostTime: 20, now: 20.1, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: true, current: 10, total: 10, nextLastPostTime: 20)
        )

        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 5, oldProgress: 4, duration: 10, lastPostTime: 20, now: 20.5, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: false, current: 5, total: 10, nextLastPostTime: 20)
        )

        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 5, oldProgress: 4, duration: 10, lastPostTime: 20, now: 21, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: true, current: 5, total: 10, nextLastPostTime: 21)
        )
    }

    func testProgressPostDecisionUsesProgressAsDurationWhenSeekingIsDisabled() {
        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 5, oldProgress: 4, duration: 10, lastPostTime: 20, now: 21, seekEnabled: false),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: true, current: 5, total: 5, nextLastPostTime: 21)
        )
    }

    func testProgressPostDecisionRejectsUnchangedOrNonFiniteProgress() {
        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 4, oldProgress: 4, duration: 10, lastPostTime: 20, now: 21, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: false, current: 4, total: 10, nextLastPostTime: 20)
        )

        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: .nan, oldProgress: 4, duration: 10, lastPostTime: 20, now: 21, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: false, current: 0, total: 10, nextLastPostTime: 20)
        )
    }
}
```

- [ ] **Step 2: Add the test file to the Xcode test target**

Edit `IRPlayer-swift.xcodeproj/project.pbxproj` following existing test-file patterns:

- Add a `PBXFileReference` for `IRPlaybackTimePolicyTests.swift`.
- Add a `PBXBuildFile` for `IRPlaybackTimePolicyTests.swift in Sources`.
- Add the file reference under the `IRPlayer-swiftTests` group.
- Add the build file under the `IRPlayer-swiftTests` target `PBXSourcesBuildPhase`.

- [ ] **Step 3: Run the focused test to verify RED**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3' -only-testing:IRPlayer-swiftTests/IRPlaybackTimePolicyTests
```

Expected: FAIL because `IRPlaybackTimePolicy` does not exist. Confirm the test target compiles the new test file and fails for the missing policy type.

- [ ] **Step 4: Commit the red test**

```sh
git add Tests/IRPlayer-swiftTests/IRPlaybackTimePolicyTests.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "test: cover playback time policy decisions"
```

## Task 2: Implement the Pure Playback Time Policy

**Files:**
- Create: `Sources/IRPlayer-swift/Class/IRPlaybackTimePolicy.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the minimal policy implementation**

Create `Sources/IRPlayer-swift/Class/IRPlaybackTimePolicy.swift`:

```swift
import Foundation

enum IRPlaybackTimePolicy {
    struct ProgressPostDecision: Equatable {
        let shouldPost: Bool
        let current: TimeInterval
        let total: TimeInterval
        let nextLastPostTime: TimeInterval
    }

    static func percent(current: TimeInterval, total: TimeInterval) -> NSNumber {
        guard current.isFinite, total.isFinite, total > 0 else {
            return NSNumber(value: 0)
        }
        let percent = current / total
        return NSNumber(value: percent.isFinite ? percent : 0)
    }

    static func clampedPlayableTime(_ playableTime: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard playableTime.isFinite, duration.isFinite, duration >= 0 else { return 0 }
        return min(max(playableTime, 0), duration)
    }

    static func clampedSeekTime(requested: TimeInterval, min minTime: TimeInterval, max maxTime: TimeInterval) -> TimeInterval? {
        guard requested.isFinite, minTime.isFinite, maxTime.isFinite else { return nil }
        let resolvedMaxTime = maxTime < minTime ? minTime : maxTime
        if requested > resolvedMaxTime {
            return resolvedMaxTime
        }
        if requested < minTime {
            return minTime
        }
        return requested
    }

    static func bufferingState(
        currentlyBuffering: Bool,
        bufferedDuration: TimeInterval,
        minBufferedDuration: TimeInterval,
        endOfFile: Bool
    ) -> Bool {
        let safeBufferedDuration = bufferedDuration.isFinite ? bufferedDuration : 0
        let safeMinBufferedDuration = minBufferedDuration.isFinite ? minBufferedDuration : 0
        if currentlyBuffering {
            return !(safeBufferedDuration >= safeMinBufferedDuration || endOfFile)
        }
        return safeBufferedDuration <= 0.2 && !endOfFile
    }

    static func progressPostDecision(
        progress: TimeInterval,
        oldProgress: TimeInterval,
        duration: TimeInterval,
        lastPostTime: TimeInterval,
        now: TimeInterval,
        seekEnabled: Bool
    ) -> ProgressPostDecision {
        let safeDuration = duration.isFinite ? duration : 0
        guard progress != oldProgress else {
            return ProgressPostDecision(shouldPost: false, current: progress, total: safeDuration, nextLastPostTime: lastPostTime)
        }
        guard progress.isFinite else {
            return ProgressPostDecision(shouldPost: false, current: 0, total: safeDuration, nextLastPostTime: lastPostTime)
        }

        if progress <= 0.000001 || progress == safeDuration {
            return ProgressPostDecision(shouldPost: true, current: progress, total: safeDuration, nextLastPostTime: lastPostTime)
        }

        guard now.isFinite, lastPostTime.isFinite, now - lastPostTime >= 1 else {
            return ProgressPostDecision(shouldPost: false, current: progress, total: safeDuration, nextLastPostTime: lastPostTime)
        }

        let effectiveDuration = seekEnabled ? safeDuration : progress
        return ProgressPostDecision(shouldPost: true, current: progress, total: effectiveDuration, nextLastPostTime: now)
    }
}
```

- [ ] **Step 2: Add the production file to the Xcode framework target**

Edit `IRPlayer-swift.xcodeproj/project.pbxproj` using existing source-file patterns:

- Add a `PBXFileReference` for `IRPlaybackTimePolicy.swift`.
- Add a `PBXBuildFile` for `IRPlaybackTimePolicy.swift in Sources`.
- Add the file reference under the main source group near `IRPlaybackTimePolicy.swift` peers such as `IRPlayerLifecyclePolicy.swift`.
- Add the build file under the `IRPlayer-swift` target `PBXSourcesBuildPhase`.

- [ ] **Step 3: Run focused policy tests to verify GREEN**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3' -only-testing:IRPlayer-swiftTests/IRPlaybackTimePolicyTests
```

Expected: PASS for `IRPlaybackTimePolicyTests`.

- [ ] **Step 4: Commit the policy helper**

```sh
git add Sources/IRPlayer-swift/Class/IRPlaybackTimePolicy.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "feat: add playback time policy helper"
```

## Task 3: Integrate Percent, Playable, and Progress Policy

**Files:**
- Modify: `Sources/IRPlayer-swift/Class/IRPlayerAction.swift`
- Modify: `Sources/IRPlayer-swift/Class/Core/FFPlayer/IRFFPlayer.swift`

- [ ] **Step 1: Route notification percent calculation through the policy**

In `IRPlayerNotificationPayload.timePercent(current:total:)`, replace the body with:

```swift
return IRPlaybackTimePolicy.percent(current: current, total: total)
```

- [ ] **Step 2: Route FFmpeg progress posting through the policy**

In `IRFFPlayer.progress.didSet`, keep the first guard and replace the remaining body with:

```swift
let decision = IRPlaybackTimePolicy.progressPostDecision(
    progress: progress,
    oldProgress: oldValue,
    duration: duration,
    lastPostTime: lastPostProgressTime,
    now: Date().timeIntervalSince1970,
    seekEnabled: decoder?.seekEnable != false
)
guard decision.shouldPost else { return }
lastPostProgressTime = decision.nextLastPostTime
IRPlayerNotification.postPlayer(
    abstractPlayer,
    progressPercent: IRPlaybackTimePolicy.percent(current: decision.current, total: decision.total),
    current: decision.current as NSNumber,
    total: decision.total as NSNumber
)
```

- [ ] **Step 3: Route FFmpeg playable clamping through the policy**

In `IRFFPlayer.playableTime.didSet`, replace the body with:

```swift
let duration = self.duration
let newPlayableTime = IRPlaybackTimePolicy.clampedPlayableTime(playableTime, duration: duration)
if playableTime != newPlayableTime {
    playableTime = newPlayableTime
    IRPlayerNotification.postPlayer(
        abstractPlayer,
        playablePercent: IRPlaybackTimePolicy.percent(current: playableTime, total: duration),
        current: playableTime as NSNumber,
        total: duration as NSNumber
    )
}
```

- [ ] **Step 4: Run focused tests**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3' -only-testing:IRPlayer-swiftTests/IRPlaybackTimePolicyTests -only-testing:IRPlayer-swiftTests/IRModelPayloadTests -only-testing:IRPlayer-swiftTests/IRFFPlayerTests
```

Expected: PASS.

- [ ] **Step 5: Commit the player-side integration**

```sh
git add Sources/IRPlayer-swift/Class/IRPlayerAction.swift Sources/IRPlayer-swift/Class/Core/FFPlayer/IRFFPlayer.swift
git commit -m "refactor: route playback time decisions through policy"
```

## Task 4: Integrate FFmpeg Seek and Buffering Policy

**Files:**
- Modify: `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift`

- [ ] **Step 1: Route seek clamping through the policy**

In `IRFFDecoder.seek(to:completeHandler:)`, keep the existing `guard seekEnable, error == nil` block and temp-duration calculation. Replace the seek bounds block with:

```swift
let tempDuration: TimeInterval = formatContext?.audioEnable == true ? 8 : 15
let seekMinTime: TimeInterval = self.seekMinTime
let rawSeekMaxTime = duration - (minBufferedDuration + tempDuration)
guard let clampedSeekTime = IRPlaybackTimePolicy.clampedSeekTime(
    requested: time,
    min: seekMinTime,
    max: rawSeekMaxTime
) else {
    completeHandler?(false)
    return
}
seekToTime = clampedSeekTime
```

Leave the following existing side effects in place:

```swift
self.progress = seekToTime
self.seekCompleteHandler = completeHandler
self.seeking = true
videoDecoder?.paused = true
if endOfFile {
    setupReadPacketOperation()
}
```

- [ ] **Step 2: Route buffering-state calculation through the policy**

Replace `checkBufferingStatus()` body with:

```swift
buffering = IRPlaybackTimePolicy.bufferingState(
    currentlyBuffering: buffering,
    bufferedDuration: bufferedDuration,
    minBufferedDuration: minBufferedDuration,
    endOfFile: endOfFile
)
```

- [ ] **Step 3: Run focused tests**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3' -only-testing:IRPlayer-swiftTests/IRPlaybackTimePolicyTests -only-testing:IRPlayer-swiftTests/IRFFFormatContextTests -only-testing:IRPlayer-swiftTests/IRFFDecoderOperationTests
```

Expected: PASS.

- [ ] **Step 4: Commit the decoder-side integration**

```sh
git add Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift
git commit -m "refactor: route ffmpeg seek buffering through policy"
```

## Task 5: Full Verification

**Files:**
- No production changes.

- [ ] **Step 1: Run whitespace and status checks**

Run:

```sh
git diff --check
git status --short
```

Expected: no whitespace errors; status is clean after Task 4 commit.

- [ ] **Step 2: Run the full iOS simulator test suite**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3'
```

Expected: all tests pass, including the existing suite plus `IRPlaybackTimePolicyTests`.

- [ ] **Step 3: Report final status**

Include:

- Commit hashes created by this plan.
- Full test result summary.
- Note that public API signatures and notification names/payload keys were preserved.
