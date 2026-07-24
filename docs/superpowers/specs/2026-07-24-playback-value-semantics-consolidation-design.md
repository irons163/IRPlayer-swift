# Playback Value Semantics Consolidation Design

Date: 2026-07-24

## Context

Four remaining policy files separate small value calculations from the types
that consume and expose them:

- `IRPlaybackTimePolicy`
- `IRPlayerNotificationPayloadPolicy`
- `IRPLFImagePolicy`
- `IRFFDecoderSeekPolicy`

The notification and image owners only forward to their policies. Decoder seek
semantics are similarly mirrored through `IRFFDecoder`, while tests compare the
two implementations. `IRPlaybackTimePolicy` mixes unrelated concerns: shared
playable-time validation, notification percentage formatting, FFPlayer
progress-event throttling, decoder seek clamping, and one buffering helper that
has no production consumer.

This structure makes ownership ambiguous and allows owner wrappers and policy
implementations to drift.

## Goals

- Give reusable playback bounds a named validated value type.
- Put notification serialization and parsing directly on
  `IRPlayerNotificationPayload`.
- Put progress-event decisions directly on `IRFFPlayerRuntime`.
- Put seek preparation and transitions directly on `IRFFDecoder`.
- Put RGB image byte-count validation at the platform image boundary that uses
  it.
- Remove dead production semantics and mirror-only tests.
- Reject non-finite inputs and finite-input derived overflow deterministically.
- Preserve public notification keys, payload shapes, model parsing, playback
  behavior, and platform image behavior.
- Remove all four policy files and their Xcode project entries.

## Non-Goals

- Changing public notification names or payload keys.
- Changing the public `IRModel`, `IRProgress`, `IRPlayable`, or `IRError`
  surface.
- Changing FFmpeg seek scheduling, queue ownership, or decoder lifecycle.
- Changing RGB channel layout, color space, or image interpolation.
- Consolidating unrelated FFmpeg audio, packet, display, or video policies in
  this slice.

## Design

### Validated playback range

Replace the mixed `IRPlaybackTimePolicy` namespace with
`IRPlaybackTimeRange`, an immutable `Equatable` and `Sendable` value. Its
initializer accepts only finite non-negative durations. Clamping accepts only
finite times and returns a value in the closed `0...duration` range.

AVPlayer and FFPlayer use this shared value directly when publishing playable
time. Invalid duration or time continues to resolve to zero at those owner
boundaries.

### Notification payload ownership

`IRPlayerNotificationPayload` constructs state, progress, playable, and error
payloads directly. It also owns numeric decoding and finite-number defaults
because those rules exist solely for the notification/model boundary.

Time percentages require finite inputs and a strictly positive total, clamp the
current value into the playable range, and publish an `NSNumber` in `0...1`.

### FFPlayer progress ownership

`IRFFPlayerRuntime` owns a nested immutable progress-post decision and the
calculation that produces it. Duration normalization and throttle elapsed-time
arithmetic validate their derived results. Start and terminal events retain
their existing immediate-post behavior.

The unused generic buffering helper is deleted instead of being relocated.
Decoder buffering already has its own richer live-stream-aware transition
semantics.

### Decoder seek ownership

`IRFFDecoder` directly owns seek preparation, resume targeting, and completion
transition semantics. Seek bounds validate every input, derive the audio/video
tail window with checked finite arithmetic, collapse an inverted maximum to the
minimum, and clamp the request to the resulting closed range.

Tests call the decoder owner. Wrapper-versus-policy comparisons are removed.

### Platform image ownership

`IRPLFImageRGBDataByteCount` directly validates positive dimensions and row
stride, verifies at least three bytes per pixel with checked multiplication,
and derives the complete byte count with checked multiplication.

Real `CGImage` and `UIImage` construction tests remain the integration
boundary.

## Test Strategy

- Add value tests for `IRPlaybackTimeRange` initialization and clamping.
- Keep percentage, numeric parsing, payload construction, and model round-trip
  tests on `IRPlayerNotificationPayload` and `IRModel`.
- Move progress-decision tables to `IRFFPlayerRuntime` tests and add derived
  elapsed-time overflow coverage.
- Rename seek-policy tests to decoder-seek semantics tests and add non-finite
  and derived-overflow tables.
- Replace platform policy mirror tests with direct exact, padded-row, minimum
  row, width-overflow, and total-overflow tests.
- Run focused owner/integration suites, affected runtime tests under Thread
  Sanitizer, the full iOS Simulator suite, and a generic iOS Release build.

## Acceptance Criteria

- No source, test, or Xcode project reference to the four deleted policies
  remains.
- Playback bounds have one immutable validated value owner.
- Notification, FFPlayer progress, decoder seek, and image byte semantics are
  tested through their actual owners.
- No production reference to the dead generic buffering helper remains.
- The source tree policy count falls from 21 to 17.
- Focused, Thread Sanitizer, full-suite, Release, project, warning, and
  whitespace gates pass.
