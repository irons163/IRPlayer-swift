# Playback Time and Buffering Policy Design

## Summary

This Phase 2 slice adds a low-risk pure policy seam for playback time, seek clamping, playable-time clamping, and buffering state decisions. The goal is to make seek and buffering correctness easier to test before changing deeper AVPlayer or FFmpeg runtime loops.

The work introduces an internal helper named `IRPlaybackTimePolicy`. Existing public APIs, notification names, notification payload keys, decoder loops, and player control flows remain source-compatible.

## Goals

- Centralize shared time math and buffering decisions in a deterministic internal helper.
- Preserve existing runtime behavior for progress percent, playable time clamping, seek clamping, and buffering enter/exit decisions.
- Add focused unit tests for finite and non-finite values, negative inputs, zero duration, seek min/max bounds, and end-of-file buffering behavior.
- Keep the implementation render-independent and playback-loop-independent.

## Non-Goals

- Do not refactor `IRFFDecoder` read/decode/display operation loops.
- Do not change AVPlayer or FFmpeg seek execution mechanics.
- Do not change public API, notification names, notification payload keys, or module usage.
- Do not change progress or playable notification timing beyond preserving existing behavior through policy calls.
- Do not attempt to make `swift test` the acceptance gate for this slice.

## Architecture

Add `Sources/IRPlayer-swift/Class/IRPlaybackTimePolicy.swift` as an internal pure helper. The helper imports Foundation only and exposes static functions for value decisions:

- `percent(current:total:) -> NSNumber`
  - Returns `current / total` for finite values with `total > 0`.
  - Returns `0` for non-finite values, zero totals, or negative totals.
- `clampedPlayableTime(_:duration:) -> TimeInterval`
  - Clamps finite playable time to `0...duration`.
  - Returns `0` when playable time or duration is non-finite, or when duration is negative.
- `clampedSeekTime(requested:min:max:) -> TimeInterval?`
  - Returns nil for non-finite inputs.
  - Normalizes inverted bounds by using `min` when `max < min`, matching the current FFmpeg seek behavior.
  - Clamps requested time into the resolved range.
- `bufferingState(currentlyBuffering:bufferedDuration:minBufferedDuration:endOfFile:) -> Bool`
  - If already buffering, exits buffering when `bufferedDuration >= minBufferedDuration` or `endOfFile == true`.
  - If not buffering, enters buffering when `bufferedDuration <= 0.2` and not end-of-file.
  - Treats non-finite durations as zero for decision purposes.
- `progressPostDecision(...)`
  - Encapsulates the existing FFmpeg progress notification throttle rule.
  - Posts immediately at start/end, otherwise posts at most once per second.
  - Uses `progress` as effective duration when seeking is disabled, preserving current live-stream behavior.

## Integration Points

Use the helper in low-risk call sites only:

- `IRPlayerNotificationPayload.timePercent` delegates to `IRPlaybackTimePolicy.percent`.
- `IRFFPlayer.playableTime.didSet` delegates playable clamping to `IRPlaybackTimePolicy.clampedPlayableTime`.
- `IRFFPlayer.progress.didSet` delegates post/no-post and effective-duration decisions to `IRPlaybackTimePolicy.progressPostDecision`.
- `IRFFDecoder.seek(to:completeHandler:)` delegates seek clamping to `IRPlaybackTimePolicy.clampedSeekTime`.
- `IRFFDecoder.checkBufferingStatus()` delegates buffering state decisions to `IRPlaybackTimePolicy.bufferingState`.

`IRAVPlayer.seekTime(for:)` already has focused tests and can stay unchanged in this slice.

## Error Handling

The policy does not throw. Invalid numeric inputs become nil or zero-value decisions, matching current defensive behavior. Existing completion handlers and notifications keep their current call sites and timing.

## Testing

Add `IRPlaybackTimePolicyTests` covering:

- Percent calculation with finite values, zero/negative totals, and non-finite current/total values.
- Playable-time clamping for negative values, over-duration values, non-finite values, and invalid durations.
- Seek-time clamping for below-min, above-max, in-range, inverted bounds, and non-finite inputs.
- Buffering state transitions for entering, staying, exiting by minimum buffer, and exiting by end-of-file.
- Progress post decision for start, end, one-second throttle, non-finite values, and seek-disabled effective duration.

Extend existing focused tests only where the integration point is already covered:

- `IRModelPayloadTests` continues to cover `IRPlayerNotificationPayload.timePercent` behavior.
- Add policy-level tests for FFmpeg seek clamping, playable clamping, progress posting, and buffering state in `IRPlaybackTimePolicyTests`; do not add decoder-loop integration tests in this slice.

## Acceptance Criteria

- `IRPlaybackTimePolicyTests` are added and fail before implementation.
- Focused policy tests pass after implementation.
- Existing notification payload tests still pass.
- Existing FFmpeg/AVPlayer focused tests still pass.
- Full iOS simulator suite passes:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3'
```

## Implementation Boundary

Place production policy code in `Sources/IRPlayer-swift/Class/IRPlaybackTimePolicy.swift`. Keep existing player and decoder files responsible for side effects, delegate callbacks, queue control, and notification posting.
