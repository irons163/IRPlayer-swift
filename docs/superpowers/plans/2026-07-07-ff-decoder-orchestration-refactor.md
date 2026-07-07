# FFmpeg Decoder Orchestration Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract read-loop and display-loop orchestration decisions from `IRFFDecoder.swift` into focused internal helpers while preserving FFmpeg playback behavior.

**Architecture:** Add value-oriented `IRFFDecoderReadLoopState` and `IRFFDecoderDisplayLoopState` helpers that describe loop actions without owning decoders, queues, FFmpeg pointers, sleeps, or callbacks. Keep `IRFFDecoder` as the owner that applies actions to concrete state, decoders, packets, frames, and delegates.

**Tech Stack:** Swift 5.9, XCTest, Xcode project source registration, FFmpeg wrapper types from `IRFFMpeg`, iOS Simulator tests through XcodeBuildMCP or `xcodebuild test`.

---

## Scope Check

This plan implements the design in
`docs/superpowers/specs/2026-07-07-ff-decoder-orchestration-refactor-design.md`.
It touches only FFmpeg decoder orchestration internals, focused tests, and the
Xcode project file registrations for new files.

## File Structure

- Create: `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderReadLoopState.swift`
  - Owns read-loop action planning for exit, seek completion, audio-track selection, backpressure, EOF, and packet routing.
- Create: `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderDisplayLoopState.swift`
  - Owns display-loop action planning for exit, idle replay, finish, audio sync waits, frame acceptance, and standalone sleeps.
- Modify: `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift`
  - Keeps concrete FFmpeg reads, packet puts, decoder flushes, frame gets, sleeps, callbacks, queue setup, and public observable state.
  - Delegates loop action decisions to the new helpers.
- Create: `Tests/IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests.swift`
  - Covers read-loop action planning without opening media.
- Create: `Tests/IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests.swift`
  - Covers display-loop action planning without opening media.
- Modify: `Tests/IRPlayer-swiftTests/IRFFDecoderOperationTests.swift`
  - Extend the static wrapper source-compatibility test if `IRFFDecoder` exposes wrapper methods for the new helpers.
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`
  - Register new production and test files.

Use these project identifiers when editing `project.pbxproj`:

- `B5E961002F7108000149265` = `IRFFDecoderReadLoopState.swift` file reference
- `B5E961012F7108000149265` = `IRFFDecoderReadLoopState.swift in Sources`
- `B5E961022F7108010149265` = `IRFFDecoderReadLoopStateTests.swift` file reference
- `B5E961032F7108010149265` = `IRFFDecoderReadLoopStateTests.swift in Sources`
- `B5E961042F7108020149265` = `IRFFDecoderDisplayLoopState.swift` file reference
- `B5E961052F7108020149265` = `IRFFDecoderDisplayLoopState.swift in Sources`
- `B5E961062F7108030149265` = `IRFFDecoderDisplayLoopStateTests.swift` file reference
- `B5E961072F7108030149265` = `IRFFDecoderDisplayLoopStateTests.swift in Sources`

Add production file references near the existing `IRFFDecoder*.swift` files in the
`FFmpeg` group. Add test file references near the existing `IRFFDecoder*Tests.swift`
files in the test group.

## Verification Commands

Before the first simulator build/test in an implementation session, call
XcodeBuildMCP `session_show_defaults`. If defaults show project/workspace, scheme,
and simulator are configured, use those defaults for focused and full test calls.

Shell fallback for focused tests:

```sh
FOCUSED_DESTINATION_ID="$(xcrun simctl list devices available | awk -F'[()]' '/iPhone/ && /Booted|Shutdown/ { print $2; exit }')"
test -n "$FOCUSED_DESTINATION_ID"
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRFFDecoderOperationTests
```

Focused FFmpeg decoder suite:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderOperationTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderAudioPolicyTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderPacketPolicyTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderSeekPolicyTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderDisplayPolicyTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderOperationPolicyTests
```

Full verification:

```sh
git diff --check
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID"
```

Expected green output for passing test runs includes `** TEST SUCCEEDED **`.

---

### Task 1: Add Read Loop State Helper

**Files:**
- Create: `Tests/IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests.swift`
- Create: `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderReadLoopState.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

- [x] **Step 1: Write the failing read-loop state tests**

Create `Tests/IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests.swift`:

```swift
import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderReadLoopStateTests: XCTestCase {

    func testExitActionQuitsForClosedOrErroredDecoder() {
        XCTAssertEqual(
            IRFFDecoderReadLoopState.exitAction(closed: true, hasError: false),
            .quit
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.exitAction(closed: false, hasError: true),
            .quit
        )
        XCTAssertNil(IRFFDecoderReadLoopState.exitAction(closed: false, hasError: false))
    }

    func testSeekCompletionActionWrapsExistingSeekTransition() {
        XCTAssertNil(IRFFDecoderReadLoopState.seekCompletionAction(seeking: false, progress: 3))
        XCTAssertEqual(
            IRFFDecoderReadLoopState.seekCompletionAction(seeking: true, progress: 3),
            .completeSeek(
                IRFFDecoder.SeekCompletionTransition(
                    endOfFile: false,
                    playbackFinished: false,
                    buffering: true,
                    videoPaused: false,
                    videoEndOfFile: false,
                    seekToTime: 0,
                    audioTimeClock: 3,
                    shouldClearFrames: true
                )
            )
        )
    }

    func testAudioTrackSelectionActionClearsSelectionAndCarriesSeekTarget() {
        XCTAssertNil(
            IRFFDecoderReadLoopState.audioTrackSelectionAction(
                selectionPending: false,
                decoderWasReset: true,
                hasAudioDecoder: true,
                playbackFinished: false,
                audioTimeClock: 12
            )
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.audioTrackSelectionAction(
                selectionPending: true,
                decoderWasReset: true,
                hasAudioDecoder: true,
                playbackFinished: false,
                audioTimeClock: 12
            ),
            IRFFDecoderReadLoopState.AudioTrackSelectionAction(
                shouldClearSelection: true,
                seekTarget: 12
            )
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.audioTrackSelectionAction(
                selectionPending: true,
                decoderWasReset: false,
                hasAudioDecoder: true,
                playbackFinished: false,
                audioTimeClock: 12
            ),
            IRFFDecoderReadLoopState.AudioTrackSelectionAction(
                shouldClearSelection: true,
                seekTarget: nil
            )
        )
    }

    func testBackpressureActionWrapsPacketPolicySleep() {
        XCTAssertNil(
            IRFFDecoderReadLoopState.backpressureAction(
                audioSize: 3,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.backpressureAction(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            ),
            .sleep(0.1)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.backpressureAction(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: true
            ),
            .sleep(0.5)
        )
    }

    func testEOFActionWrapsPacketEOFTransition() {
        XCTAssertNil(IRFFDecoderReadLoopState.eofAction(readFrameResult: 0))
        XCTAssertEqual(
            IRFFDecoderReadLoopState.eofAction(readFrameResult: -1),
            .finishEOF(
                IRFFDecoder.ReadPacketEOFTransition(
                    endOfFile: true,
                    videoEndOfFile: true,
                    shouldFinishReadLoop: true,
                    shouldNotifyDelegate: true
                )
            )
        )
    }

    func testPacketActionRoutesByTrackIndexes() {
        XCTAssertEqual(
            IRFFDecoderReadLoopState.packetAction(
                streamIndex: 2,
                videoTrackIndex: 2,
                audioTrackIndex: 3
            ),
            .routePacket(.video)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.packetAction(
                streamIndex: 3,
                videoTrackIndex: 2,
                audioTrackIndex: 3
            ),
            .routePacket(.audio)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.packetAction(
                streamIndex: 4,
                videoTrackIndex: 2,
                audioTrackIndex: 3
            ),
            .routePacket(.ignored)
        )
    }
}
```

- [x] **Step 2: Add the test file to the Xcode test target**

Modify `IRPlayer-swift.xcodeproj/project.pbxproj`:

```text
B5E961032F7108010149265 /* IRFFDecoderReadLoopStateTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B5E961022F7108010149265 /* IRFFDecoderReadLoopStateTests.swift */; };
B5E961022F7108010149265 /* IRFFDecoderReadLoopStateTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IRFFDecoderReadLoopStateTests.swift; sourceTree = "<group>"; };
B5E961022F7108010149265 /* IRFFDecoderReadLoopStateTests.swift */,
B5E961032F7108010149265 /* IRFFDecoderReadLoopStateTests.swift in Sources */,
```

- [x] **Step 3: Run the focused read-loop tests and confirm RED**

Run:

```sh
FOCUSED_DESTINATION_ID="$(xcrun simctl list devices available | awk -F'[()]' '/iPhone/ && /Booted|Shutdown/ { print $2; exit }')"
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests
```

Expected: FAIL to compile with `cannot find 'IRFFDecoderReadLoopState' in scope`.

- [x] **Step 4: Implement the read-loop state helper**

Create `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderReadLoopState.swift`:

```swift
//
//  IRFFDecoderReadLoopState.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import Foundation

enum IRFFDecoderReadLoopState {

    enum Action: Equatable {
        case quit
        case completeSeek(IRFFDecoder.SeekCompletionTransition)
        case sleep(TimeInterval)
        case finishEOF(IRFFDecoder.ReadPacketEOFTransition)
        case routePacket(IRFFDecoder.PacketRoute)
    }

    struct AudioTrackSelectionAction: Equatable {
        let shouldClearSelection: Bool
        let seekTarget: TimeInterval?
    }

    static func exitAction(closed: Bool, hasError: Bool) -> Action? {
        return closed || hasError ? .quit : nil
    }

    static func seekCompletionAction(seeking: Bool, progress: TimeInterval) -> Action? {
        guard let transition = IRFFDecoderSeekPolicy.seekCompletionTransition(
            seeking: seeking,
            progress: progress
        ) else {
            return nil
        }
        return .completeSeek(transition)
    }

    static func audioTrackSelectionAction(selectionPending: Bool,
                                          decoderWasReset: Bool,
                                          hasAudioDecoder: Bool,
                                          playbackFinished: Bool,
                                          audioTimeClock: TimeInterval) -> AudioTrackSelectionAction? {
        guard selectionPending else { return nil }
        let seekTarget = IRFFDecoderSeekPolicy.audioTrackSelectionSeekTarget(
            selectionPending: selectionPending,
            decoderWasReset: decoderWasReset,
            hasAudioDecoder: hasAudioDecoder,
            playbackFinished: playbackFinished,
            audioTimeClock: audioTimeClock
        )
        return AudioTrackSelectionAction(shouldClearSelection: true, seekTarget: seekTarget)
    }

    static func backpressureAction(audioSize: Int,
                                   videoPacketSize: Int,
                                   maxBufferSize: Int = 20 * 1024 * 1024,
                                   paused: Bool) -> Action? {
        guard let interval = IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
            audioSize: audioSize,
            videoPacketSize: videoPacketSize,
            maxBufferSize: maxBufferSize,
            paused: paused
        ) else {
            return nil
        }
        return .sleep(interval)
    }

    static func eofAction(readFrameResult: Int32?) -> Action? {
        guard let transition = IRFFDecoderPacketPolicy.readPacketEOFTransition(
            readFrameResult: readFrameResult
        ) else {
            return nil
        }
        return .finishEOF(transition)
    }

    static func packetAction(streamIndex: Int32,
                             videoTrackIndex: Int?,
                             audioTrackIndex: Int?) -> Action {
        let route = IRFFDecoderPacketPolicy.packetRoute(
            streamIndex: streamIndex,
            videoTrackIndex: videoTrackIndex,
            audioTrackIndex: audioTrackIndex
        )
        return .routePacket(route)
    }
}
```

- [x] **Step 5: Add the source file to the Xcode framework target**

Modify `IRPlayer-swift.xcodeproj/project.pbxproj`:

```text
B5E961012F7108000149265 /* IRFFDecoderReadLoopState.swift in Sources */ = {isa = PBXBuildFile; fileRef = B5E961002F7108000149265 /* IRFFDecoderReadLoopState.swift */; };
B5E961002F7108000149265 /* IRFFDecoderReadLoopState.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IRFFDecoderReadLoopState.swift; sourceTree = "<group>"; };
B5E961002F7108000149265 /* IRFFDecoderReadLoopState.swift */,
B5E961012F7108000149265 /* IRFFDecoderReadLoopState.swift in Sources */,
```

- [x] **Step 6: Run focused read-loop tests and confirm GREEN**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [x] **Step 7: Commit**

Run:

```sh
git add Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderReadLoopState.swift Tests/IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "feat: add ff decoder read loop state"
```

---

### Task 2: Add Display Loop State Helper

**Files:**
- Create: `Tests/IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests.swift`
- Create: `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderDisplayLoopState.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

- [x] **Step 1: Write the failing display-loop state tests**

Create `Tests/IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests.swift`:

```swift
import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderDisplayLoopStateTests: XCTestCase {

    func testExitActionQuitsForClosedOrErroredDecoder() {
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.exitAction(closed: true, hasError: false),
            .quit
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.exitAction(closed: false, hasError: true),
            .quit
        )
        XCTAssertNil(IRFFDecoderDisplayLoopState.exitAction(closed: false, hasError: false))
    }

    func testIdleActionPreservesSeekingBufferingAndPausedReplay() {
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: true,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            .idleSleep(interval: 0.01, replayCurrentFrame: false)
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: false,
                buffering: true,
                paused: false,
                hasCurrentFrame: false
            ),
            .idleSleep(interval: 0.01, replayCurrentFrame: false)
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            .idleSleep(interval: 0.03, replayCurrentFrame: true)
        )
        XCTAssertNil(
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: false,
                buffering: false,
                paused: false,
                hasCurrentFrame: true
            )
        )
    }

    func testFinishActionRequiresEndOfFileAndEmptyVideoQueue() {
        XCTAssertNil(IRFFDecoderDisplayLoopState.finishAction(endOfFile: false, videoDecoderEmpty: true))
        XCTAssertNil(IRFFDecoderDisplayLoopState.finishAction(endOfFile: true, videoDecoderEmpty: false))
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.finishAction(endOfFile: true, videoDecoderEmpty: true),
            .finish
        )
    }

    func testAudioSyncActionWaitsForAudioClock() {
        XCTAssertNil(
            IRFFDecoderDisplayLoopState.audioSyncAction(
                currentFramePosition: nil,
                currentFrameDuration: nil,
                audioTimeClock: 9,
                fps: 25
            )
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.audioSyncAction(
                currentFramePosition: 10,
                currentFrameDuration: 0.04,
                audioTimeClock: 9,
                fps: 25
            ),
            .waitForAudio(interval: 0.02)
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.audioSyncAction(
                currentFramePosition: 10,
                currentFrameDuration: 0.02,
                audioTimeClock: 10.01,
                fps: 25
            ),
            .waitForAudio(interval: 0.015)
        )
    }

    func testFrameAcceptanceUsesDisplayPolicyOrdering() {
        XCTAssertTrue(
            IRFFDecoderDisplayLoopState.shouldAcceptFrame(
                currentPosition: nil,
                nextPosition: 0.5
            )
        )
        XCTAssertTrue(
            IRFFDecoderDisplayLoopState.shouldAcceptFrame(
                currentPosition: 1,
                nextPosition: 1
            )
        )
        XCTAssertFalse(
            IRFFDecoderDisplayLoopState.shouldAcceptFrame(
                currentPosition: 1,
                nextPosition: 0.5
            )
        )
        XCTAssertFalse(
            IRFFDecoderDisplayLoopState.shouldAcceptFrame(
                currentPosition: 1,
                nextPosition: .nan
            )
        )
    }

    func testStandaloneSleepActionUsesFrameDurationOrFPSFallback() {
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.standaloneSleepAction(frameDuration: 0.04, fps: 25),
            .sleepAfterFrame(interval: 0.04)
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.standaloneSleepAction(frameDuration: 0, fps: 25),
            .sleepAfterFrame(interval: 0.04)
        )
        XCTAssertNil(IRFFDecoderDisplayLoopState.standaloneSleepAction(frameDuration: 0, fps: 0))
    }
}
```

- [x] **Step 2: Add the test file to the Xcode test target**

Modify `IRPlayer-swift.xcodeproj/project.pbxproj`:

```text
B5E961072F7108030149265 /* IRFFDecoderDisplayLoopStateTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B5E961062F7108030149265 /* IRFFDecoderDisplayLoopStateTests.swift */; };
B5E961062F7108030149265 /* IRFFDecoderDisplayLoopStateTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IRFFDecoderDisplayLoopStateTests.swift; sourceTree = "<group>"; };
B5E961062F7108030149265 /* IRFFDecoderDisplayLoopStateTests.swift */,
B5E961072F7108030149265 /* IRFFDecoderDisplayLoopStateTests.swift in Sources */,
```

- [x] **Step 3: Run the focused display-loop tests and confirm RED**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests
```

Expected: FAIL to compile with `cannot find 'IRFFDecoderDisplayLoopState' in scope`.

- [x] **Step 4: Implement the display-loop state helper**

Create `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderDisplayLoopState.swift`:

```swift
//
//  IRFFDecoderDisplayLoopState.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import Foundation

enum IRFFDecoderDisplayLoopState {

    enum Action: Equatable {
        case quit
        case idleSleep(interval: TimeInterval, replayCurrentFrame: Bool)
        case finish
        case waitForAudio(interval: TimeInterval)
        case sleepAfterFrame(interval: TimeInterval)
    }

    static func exitAction(closed: Bool, hasError: Bool) -> Action? {
        return closed || hasError ? .quit : nil
    }

    static func idleAction(seeking: Bool,
                           buffering: Bool,
                           paused: Bool,
                           hasCurrentFrame: Bool) -> Action? {
        guard let interval = IRFFDecoderDisplayPolicy.displayIdleSleepInterval(
            seeking: seeking,
            buffering: buffering,
            paused: paused,
            hasCurrentFrame: hasCurrentFrame
        ) else {
            return nil
        }
        return .idleSleep(
            interval: interval,
            replayCurrentFrame: paused && !seeking && !buffering && hasCurrentFrame
        )
    }

    static func finishAction(endOfFile: Bool, videoDecoderEmpty: Bool) -> Action? {
        return IRFFDecoderDisplayPolicy.shouldFinishDisplay(
            endOfFile: endOfFile,
            videoDecoderEmpty: videoDecoderEmpty
        ) ? .finish : nil
    }

    static func audioSyncAction(currentFramePosition: TimeInterval?,
                                currentFrameDuration: TimeInterval?,
                                audioTimeClock: TimeInterval,
                                fps: TimeInterval) -> Action? {
        guard let currentFramePosition,
              let currentFrameDuration,
              let interval = IRFFDecoderDisplayPolicy.audioSyncedVideoSleepDuration(
                framePosition: currentFramePosition,
                frameDuration: currentFrameDuration,
                audioTimeClock: audioTimeClock,
                fps: fps
              ) else {
            return nil
        }
        return .waitForAudio(interval: interval)
    }

    static func shouldAcceptFrame(currentPosition: TimeInterval?,
                                  nextPosition: TimeInterval?) -> Bool {
        return IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(
            currentPosition: currentPosition,
            nextPosition: nextPosition
        )
    }

    static func standaloneSleepAction(frameDuration: TimeInterval, fps: TimeInterval) -> Action? {
        guard let interval = IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(
            frameDuration: frameDuration,
            fps: fps
        ) else {
            return nil
        }
        return .sleepAfterFrame(interval: interval)
    }
}
```

- [x] **Step 5: Add the source file to the Xcode framework target**

Modify `IRPlayer-swift.xcodeproj/project.pbxproj`:

```text
B5E961052F7108020149265 /* IRFFDecoderDisplayLoopState.swift in Sources */ = {isa = PBXBuildFile; fileRef = B5E961042F7108020149265 /* IRFFDecoderDisplayLoopState.swift */; };
B5E961042F7108020149265 /* IRFFDecoderDisplayLoopState.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IRFFDecoderDisplayLoopState.swift; sourceTree = "<group>"; };
B5E961042F7108020149265 /* IRFFDecoderDisplayLoopState.swift */,
B5E961052F7108020149265 /* IRFFDecoderDisplayLoopState.swift in Sources */,
```

- [x] **Step 6: Run focused display-loop tests and confirm GREEN**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [x] **Step 7: Commit**

Run:

```sh
git add Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderDisplayLoopState.swift Tests/IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "feat: add ff decoder display loop state"
```

---

### Task 3: Route IRFFDecoder Through Loop State Helpers

**Files:**
- Modify: `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift`
- Modify: `Tests/IRPlayer-swiftTests/IRFFDecoderOperationTests.swift`

- [x] **Step 1: Add source-compatible wrapper assertions**

In `Tests/IRPlayer-swiftTests/IRFFDecoderOperationTests.swift`, append these
assertions to `testStaticPolicyWrappersRemainSourceCompatible()`:

```swift
        XCTAssertEqual(
            IRFFDecoder.readLoopExitAction(closed: true, hasError: false),
            IRFFDecoderReadLoopState.exitAction(closed: true, hasError: false)
        )
        XCTAssertEqual(
            IRFFDecoder.readLoopSeekCompletionAction(seeking: true, progress: 3),
            IRFFDecoderReadLoopState.seekCompletionAction(seeking: true, progress: 3)
        )
        XCTAssertEqual(
            IRFFDecoder.displayLoopIdleAction(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            )
        )
        XCTAssertEqual(
            IRFFDecoder.displayLoopFinishAction(endOfFile: true, videoDecoderEmpty: true),
            IRFFDecoderDisplayLoopState.finishAction(endOfFile: true, videoDecoderEmpty: true)
        )
```

- [x] **Step 2: Run operation tests and confirm RED**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRFFDecoderOperationTests/testStaticPolicyWrappersRemainSourceCompatible
```

Expected: FAIL to compile with missing static methods on `IRFFDecoder`.

- [x] **Step 3: Add static wrapper methods to `IRFFDecoder`**

In `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift`, after
`static func shouldNotifyError(closed:hasError:)`, add:

```swift
    static func readLoopExitAction(closed: Bool, hasError: Bool) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.exitAction(closed: closed, hasError: hasError)
    }

    static func readLoopSeekCompletionAction(seeking: Bool,
                                             progress: TimeInterval) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.seekCompletionAction(seeking: seeking, progress: progress)
    }

    static func readLoopAudioTrackSelectionAction(selectionPending: Bool,
                                                  decoderWasReset: Bool,
                                                  hasAudioDecoder: Bool,
                                                  playbackFinished: Bool,
                                                  audioTimeClock: TimeInterval) -> IRFFDecoderReadLoopState.AudioTrackSelectionAction? {
        return IRFFDecoderReadLoopState.audioTrackSelectionAction(
            selectionPending: selectionPending,
            decoderWasReset: decoderWasReset,
            hasAudioDecoder: hasAudioDecoder,
            playbackFinished: playbackFinished,
            audioTimeClock: audioTimeClock
        )
    }

    static func readLoopBackpressureAction(audioSize: Int,
                                           videoPacketSize: Int,
                                           paused: Bool) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.backpressureAction(
            audioSize: audioSize,
            videoPacketSize: videoPacketSize,
            paused: paused
        )
    }

    static func readLoopEOFAction(readFrameResult: Int32?) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.eofAction(readFrameResult: readFrameResult)
    }

    static func readLoopPacketAction(streamIndex: Int32,
                                     videoTrackIndex: Int?,
                                     audioTrackIndex: Int?) -> IRFFDecoderReadLoopState.Action {
        return IRFFDecoderReadLoopState.packetAction(
            streamIndex: streamIndex,
            videoTrackIndex: videoTrackIndex,
            audioTrackIndex: audioTrackIndex
        )
    }

    static func displayLoopExitAction(closed: Bool,
                                      hasError: Bool) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.exitAction(closed: closed, hasError: hasError)
    }

    static func displayLoopIdleAction(seeking: Bool,
                                      buffering: Bool,
                                      paused: Bool,
                                      hasCurrentFrame: Bool) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.idleAction(
            seeking: seeking,
            buffering: buffering,
            paused: paused,
            hasCurrentFrame: hasCurrentFrame
        )
    }

    static func displayLoopFinishAction(endOfFile: Bool,
                                        videoDecoderEmpty: Bool) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.finishAction(
            endOfFile: endOfFile,
            videoDecoderEmpty: videoDecoderEmpty
        )
    }

    static func displayLoopAudioSyncAction(currentFramePosition: TimeInterval?,
                                           currentFrameDuration: TimeInterval?,
                                           audioTimeClock: TimeInterval,
                                           fps: TimeInterval) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.audioSyncAction(
            currentFramePosition: currentFramePosition,
            currentFrameDuration: currentFrameDuration,
            audioTimeClock: audioTimeClock,
            fps: fps
        )
    }

    static func shouldAcceptDisplayFrame(currentPosition: TimeInterval?,
                                         nextPosition: TimeInterval?) -> Bool {
        return IRFFDecoderDisplayLoopState.shouldAcceptFrame(
            currentPosition: currentPosition,
            nextPosition: nextPosition
        )
    }

    static func displayLoopStandaloneSleepAction(frameDuration: TimeInterval,
                                                 fps: TimeInterval) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.standaloneSleepAction(
            frameDuration: frameDuration,
            fps: fps
        )
    }
```

- [x] **Step 4: Route `readPacketThread()` through read-loop actions**

In `readPacketThread()`, replace the top exit check:

```swift
            if closed || error != nil {
                IRFFRuntimeDebugOutput.write("read packet thread quit")
                break
            }
```

with:

```swift
            if Self.readLoopExitAction(closed: closed, hasError: error != nil) == .quit {
                IRFFRuntimeDebugOutput.write("read packet thread quit")
                break
            }
```

Replace:

```swift
            if let transition = Self.seekCompletionTransition(seeking: seeking, progress: progress) {
```

with:

```swift
            if case let .completeSeek(transition)? = Self.readLoopSeekCompletionAction(
                seeking: seeking,
                progress: progress
            ) {
```

Replace the audio-track selection seek-target block:

```swift
                    if let seekTarget = Self.audioTrackSelectionSeekTarget(
                        selectionPending: selectAudioTrack,
                        decoderWasReset: decoderWasReset,
                        hasAudioDecoder: audioDecoder != nil,
                        playbackFinished: playbackFinished,
                        audioTimeClock: audioTimeClock
                    ) {
                        seek(to: seekTarget)
                    }
```

with:

```swift
                    let selectionAction = Self.readLoopAudioTrackSelectionAction(
                        selectionPending: selectAudioTrack,
                        decoderWasReset: decoderWasReset,
                        hasAudioDecoder: audioDecoder != nil,
                        playbackFinished: playbackFinished,
                        audioTimeClock: audioTimeClock
                    )
                    if let seekTarget = selectionAction?.seekTarget {
                        seek(to: seekTarget)
                    }
```

Replace:

```swift
            if let interval = Self.packetBufferBackpressureSleepInterval(audioSize: size,
                                                                         videoPacketSize: packetSize,
                                                                         paused: paused) {
```

with:

```swift
            if case let .sleep(interval)? = Self.readLoopBackpressureAction(
                audioSize: size,
                videoPacketSize: packetSize,
                paused: paused
            ) {
```

Replace:

```swift
            if let transition = Self.readPacketEOFTransition(readFrameResult: result) {
```

with:

```swift
            if case let .finishEOF(transition)? = Self.readLoopEOFAction(readFrameResult: result) {
```

Replace:

```swift
            switch Self.packetRoute(
                streamIndex: packet.stream_index,
                videoTrackIndex: formatContext?.videoTrack?.index,
                audioTrackIndex: formatContext?.audioTrack?.index
            ) {
```

with:

```swift
            let packetAction = Self.readLoopPacketAction(
                streamIndex: packet.stream_index,
                videoTrackIndex: formatContext?.videoTrack?.index,
                audioTrackIndex: formatContext?.audioTrack?.index
            )
            switch packetAction {
            case .routePacket(.video):
```

Then update the remaining switch cases in that switch from:

```swift
            case .audio:
```

to:

```swift
            case .routePacket(.audio):
```

and from:

```swift
            case .ignored:
                break
```

to:

```swift
            case .routePacket(.ignored):
                break
            case .quit, .completeSeek(_), .sleep(_), .finishEOF(_):
                break
```

- [x] **Step 5: Route `displayThread()` through display-loop actions**

In `displayThread()`, replace:

```swift
            if closed || error != nil {
                IRFFRuntimeDebugOutput.write("display thread quit")
                break
            }
```

with:

```swift
            if Self.displayLoopExitAction(closed: closed, hasError: error != nil) == .quit {
                IRFFRuntimeDebugOutput.write("display thread quit")
                break
            }
```

Replace the idle block:

```swift
            if let sleepTime = Self.displayIdleSleepInterval(
                seeking: seeking,
                buffering: buffering,
                paused: paused,
                hasCurrentFrame: currentVideoFrame != nil
            ) {
                if paused, !seeking, !buffering, let currentFrame = currentVideoFrame {
                    videoOutput?.send?(videoFrame: currentFrame)
                }
                Thread.sleep(forTimeInterval: sleepTime)
                continue
            }
```

with:

```swift
            if case let .idleSleep(interval: sleepTime, replayCurrentFrame: replayCurrentFrame)? = Self.displayLoopIdleAction(
                seeking: seeking,
                buffering: buffering,
                paused: paused,
                hasCurrentFrame: currentVideoFrame != nil
            ) {
                if replayCurrentFrame, let currentFrame = currentVideoFrame {
                    videoOutput?.send?(videoFrame: currentFrame)
                }
                Thread.sleep(forTimeInterval: sleepTime)
                continue
            }
```

Replace:

```swift
            if Self.shouldFinishDisplay(endOfFile: endOfFile, videoDecoderEmpty: videoDecoder?.empty() ?? true) {
```

with:

```swift
            if Self.displayLoopFinishAction(endOfFile: endOfFile, videoDecoderEmpty: videoDecoder?.empty() ?? true) == .finish {
```

Replace:

```swift
                    if let sleepTime = Self.audioSyncedVideoSleepDuration(
                        framePosition: currentFrame.position,
                        frameDuration: currentFrame.duration,
                        audioTimeClock: audioTimeClock,
                        fps: videoDecoder?.fps ?? 1
                    ) {
```

with:

```swift
                    if case let .waitForAudio(interval: sleepTime)? = Self.displayLoopAudioSyncAction(
                        currentFramePosition: currentFrame.position,
                        currentFrameDuration: currentFrame.duration,
                        audioTimeClock: audioTimeClock,
                        fps: videoDecoder?.fps ?? 1
                    ) {
```

Replace both occurrences of:

```swift
                if !Self.shouldAcceptVideoFrame(currentPosition: currentVideoFrame?.position,
                                                nextPosition: newFrame?.position) {
```

with:

```swift
                if !Self.shouldAcceptDisplayFrame(currentPosition: currentVideoFrame?.position,
                                                  nextPosition: newFrame?.position) {
```

Replace:

```swift
                    if let sleepTime = Self.standaloneVideoSleepDuration(frameDuration: currentFrame.duration, fps: videoDecoder?.fps ?? 1) {
                        Thread.sleep(forTimeInterval: sleepTime)
                    }
```

with:

```swift
                    if case let .sleepAfterFrame(interval: sleepTime)? = Self.displayLoopStandaloneSleepAction(
                        frameDuration: currentFrame.duration,
                        fps: videoDecoder?.fps ?? 1
                    ) {
                        Thread.sleep(forTimeInterval: sleepTime)
                    }
```

- [x] **Step 6: Run routed focused tests and confirm GREEN**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderOperationTests
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [x] **Step 7: Commit**

Run:

```sh
git add Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift Tests/IRPlayer-swiftTests/IRFFDecoderOperationTests.swift
git commit -m "refactor: route ff decoder loops through state helpers"
```

---

### Task 4: Final Verification And Cleanup

**Files:**
- Modify only files from Tasks 1-3 if verification exposes issues inside this slice.

- [x] **Step 1: Confirm boundary and changed files**

Run:

```sh
git diff --name-only main...HEAD
```

Expected output contains only:

```text
IRPlayer-swift.xcodeproj/project.pbxproj
Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift
Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderDisplayLoopState.swift
Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderReadLoopState.swift
Tests/IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests.swift
Tests/IRPlayer-swiftTests/IRFFDecoderOperationTests.swift
Tests/IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests.swift
docs/superpowers/plans/2026-07-07-ff-decoder-orchestration-refactor.md
docs/superpowers/specs/2026-07-07-ff-decoder-orchestration-refactor-design.md
```

- [x] **Step 2: Run whitespace check**

Run:

```sh
git diff --check
```

Expected: exits `0` with no output.

- [x] **Step 3: Run focused FFmpeg decoder suite**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderOperationTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderAudioPolicyTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderPacketPolicyTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderSeekPolicyTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderDisplayPolicyTests \
  -only-testing:IRPlayer-swiftTests/IRFFDecoderOperationPolicyTests
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [x] **Step 4: Run full iOS simulator suite**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID"
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [x] **Step 5: Commit verification fixes when verification created changes**

If Tasks 4.1-4.4 require edits, run:

```sh
git status --short
git add Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderDisplayLoopState.swift Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoderReadLoopState.swift Tests/IRPlayer-swiftTests/IRFFDecoderDisplayLoopStateTests.swift Tests/IRPlayer-swiftTests/IRFFDecoderOperationTests.swift Tests/IRPlayer-swiftTests/IRFFDecoderReadLoopStateTests.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "fix: stabilize ff decoder orchestration refactor"
```

Expected: no commit is created if verification required no edits.

- [x] **Step 6: Report final status**

Report:

```text
- Branch name
- Final commit list
- Files changed
- Focused FFmpeg decoder suite result
- Full simulator suite result
- Any known residual risks
```
