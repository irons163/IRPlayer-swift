# FFmpeg Decoder Orchestration Refactor Design

## Summary

This refactor slice continues the post-2.0 modernization by reducing
`IRFFDecoder.swift` orchestration responsibility without changing playback
behavior, public APIs, FFmpeg decode semantics, audio output timing, or video
frame delivery.

`IRFFDecoder` remains the owner of the FFmpeg format context, audio decoder,
video decoder, operation queue, delegate callbacks, and public playback
controls. The goal is to move read-loop and display-loop decision flow into
small internal collaborators or state helpers so the decoder can be reasoned
about and tested in narrower pieces.

## Goals

- Preserve source compatibility for `IRFFDecoder`, `IRFFDecoderVideoOutput`,
  `IRFFDecoderAudioOutput`, and delegate-facing behavior.
- Keep current read, decode, display, seek, buffering, EOF, and progress
  semantics equivalent.
- Reduce `IRFFDecoder.swift` responsibility by extracting loop orchestration
  decisions into internal FFmpeg helpers.
- Keep `OperationQueue` scheduling, operation dependencies, and QoS behavior
  unchanged.
- Add focused tests before moving production logic so seek completion,
  audio-track selection, EOF handling, packet routing, display idle behavior,
  frame ordering, and progress updates remain pinned.
- Keep integration coverage for generated audio/video media flows passing.

## Non-Goals

- Do not change public player APIs, decoder protocols, delegate methods, or
  notification payload behavior.
- Do not rewrite `IRFFFormatContext`, `IRFFAudioDecoder`, `IRFFVideoDecoder`,
  `IRFFVideoToolBox`, frame queues, packet queues, or FFmpeg C interop.
- Do not alter AVPlayer, audio manager, display/rendering, gestures, sensors,
  or release metadata in this slice.
- Do not change buffering thresholds, seek clamping rules, video frame
  acceptance ordering, or audio/video clock synchronization math.
- Do not replace the existing `OperationQueue` model with Swift concurrency,
  GCD-only loops, actors, or async sequences.

## Current Context

`IRFFDecoder.swift` currently owns several responsibilities at once:

- FFmpeg setup and one-time runtime initialization.
- Operation queue creation, dependency wiring, and operation lifetime.
- Format context opening and decoder construction.
- Packet read loop, seek completion, audio-track switching, packet backpressure,
  EOF transition, packet routing, and audio packet error handling.
- Display loop, idle replay while paused, audio-synced video sleep, standalone
  video sleep, video frame ordering, frame output, progress updates, and EOF
  display completion.
- Audio frame fetching, audio progress updates, buffering state checks, close
  cleanup, and delegate notifications.

Several pure policy helpers already exist:

- `IRFFDecoderOperationPolicy`
- `IRFFDecoderCodecContextPolicy`
- `IRFFDecoderAudioPolicy`
- `IRFFDecoderBufferingPolicy`
- `IRFFDecoderPacketPolicy`
- `IRFFDecoderSeekPolicy`
- `IRFFDecoderDisplayPolicy`

The next improvement should build on those helpers rather than replace them.

## Architecture

Add internal-only collaborators under
`Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/`.

The preferred first split is:

- `IRFFDecoderReadLoopState`
- `IRFFDecoderDisplayLoopState`

These helpers are value-oriented where possible. They should describe the
state transitions and actions the owner must apply, while leaving concrete
decoder ownership and side effects in `IRFFDecoder`.

`IRFFDecoder` remains the mutable owner of:

- `IRFFFormatContext`
- `IRFFAudioDecoder`
- `IRFFVideoDecoder`
- `OperationQueue` and `Operation` instances
- delegate and output references
- public observable state such as `progress`, `bufferedDuration`, `buffering`,
  `endOfFile`, `paused`, `seeking`, and `playbackFinished`

The new helpers should not own FFmpeg pointers, run threads, sleep directly,
send delegate callbacks, or retain audio/video decoders.

## Component Boundaries

### `IRFFDecoder`

Keeps:

- Public/internal decoder API and protocol conformances.
- Operation queue setup and operation scheduling.
- Format context opening and concrete decoder creation.
- Actual FFmpeg reads, packet puts, frame gets, sleeps, delegate callbacks, and
  output frame sends.
- Close/destroy lifecycle.

Delegates:

- Read-loop transition interpretation to `IRFFDecoderReadLoopState`.
- Display-loop transition interpretation to `IRFFDecoderDisplayLoopState`.
- Existing pure math and guard decisions to the existing policy helpers.

### `IRFFDecoderReadLoopState`

Owns:

- Structs describing the current read-loop inputs and requested actions.
- Seek completion action planning from the current decoder state.
- Audio-track selection action planning from pending selection state and format
  context selection result.
- EOF action planning from `readFrame` results.
- Packet routing action planning using stream indexes.

Does not own:

- `IRFFFormatContext`
- audio/video decoder instances
- `AVPacket` memory lifetime
- operation scheduling
- delegate callbacks

### `IRFFDecoderDisplayLoopState`

Owns:

- Structs describing display-loop inputs and requested actions.
- Idle-state planning for seeking, buffering, and paused frame replay.
- Audio-synced and standalone video-frame display planning.
- Frame acceptance and display-finish decisions.

Does not own:

- frame queues
- output callbacks
- thread sleeps
- progress mutation
- decoder destruction

## Data Flow

`IRFFDecoder.readPacketThread()` remains the loop that performs concrete work.
For each iteration it gathers a snapshot of owner state and asks the read-loop
helper which action should happen next. `IRFFDecoder` then applies that action:

1. Quit when closed or errored.
2. Apply pending seek completion.
3. Apply pending audio-track selection.
4. Apply packet-buffer backpressure sleep.
5. Read one packet.
6. Apply EOF transition when `readFrame` fails.
7. Route packet to video, audio, or ignored handling.

`IRFFDecoder.displayThread()` remains the loop that performs concrete display
work. For each iteration it gathers owner state and asks the display-loop helper
which action should happen next:

1. Quit when closed or errored.
2. Sleep or replay current frame while idle.
3. Finish when EOF and video queues are empty.
4. Fetch and accept a new video frame.
5. Send the frame and update progress.
6. Sleep according to audio-sync or standalone-video rules.

The helpers return explicit action enums or small transition structs. They do
not mutate decoder state directly.

## Threading

The current threading model stays intact:

- `IRFFDecoder` continues to run open, read, decode, and display work on the
  existing `OperationQueue`.
- The read and display helpers are called from the same operation threads that
  currently execute the logic.
- Helpers must not add new locks, main-thread hops, queues, or blocking calls.
- Existing `Thread.sleep` behavior remains in `IRFFDecoder`, not in helpers.

## Error Handling

Existing guard-based behavior must be preserved:

- Closed or errored decoder loops exit without extra callbacks.
- Format-open errors still call `delegateErrorCallback()` once when appropriate.
- Audio packet send failures still convert through
  `IRFFDecoderAudioPolicy.audioPacketError`.
- EOF still sets `endOfFile`, propagates video EOF, finishes the read loop, and
  notifies `decoderDidEndOfFile`.
- Unsupported or ignored packets are still released by the existing loop
  lifetime behavior.
- Buffering status is checked at the same lifecycle points.

The new helpers should avoid throwing. Invalid or incomplete inputs should map
to explicit no-op or quit actions.

## Testing

Use test-first changes for production refactor steps.

Add focused tests for the new helpers before moving owner logic:

- Seek completion action resets EOF/playback/buffering/video paused/video EOF,
  clears frames, and carries the new audio clock.
- Audio-track selection action only requests a seek when selection is pending,
  the decoder was rebuilt, audio decoding is available, and playback has not
  already finished.
- EOF action preserves the current end-of-file delegate behavior.
- Packet routing action preserves video/audio/ignored routing.
- Display idle action preserves the seek/buffering sleep and paused-frame replay
  behavior.
- Display frame action preserves audio-sync wait, standalone-video sleep, frame
  ordering, and EOF finish behavior.

Keep existing integration tests as the behavior guard:

- `IRFFDecoderOperationTests`
- `IRFFDecoderAudioPolicyTests`
- `IRFFDecoderPacketPolicyTests`
- `IRFFDecoderSeekPolicyTests`
- `IRFFDecoderDisplayPolicyTests`
- Generated tiny video and audio media tests inside `IRFFDecoderOperationTests`

Focused acceptance should run all `IRFFDecoder*` tests before the full simulator
suite.

## Acceptance Criteria

- No public API signatures are changed.
- `IRFFDecoder.swift` no longer directly owns all read-loop and display-loop
  decision branching.
- New collaborators are internal-only and covered by focused tests.
- Existing generated audio/video decoder integration tests pass.
- Focused `IRFFDecoder*` test suite passes.
- Full iOS simulator suite passes.
- `git diff --check` passes.

## Implementation Boundary

This slice may edit:

- `Sources/IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/IRFFDecoder.swift`
- New internal FFmpeg decoder orchestration helper files.
- Focused tests under `Tests/IRPlayer-swiftTests/`.
- `IRPlayer-swift.xcodeproj/project.pbxproj` only to register new source/test
  files.

This slice should avoid editing:

- `Sources/IRPlayer-swift/Class/Core/AVPlayer/`
- `Sources/IRPlayer-swift/Class/Core/Audio/`
- `Sources/IRPlayer-swift/Class/Core/Display/`
- FFmpeg wrapper headers, binary frameworks, and Objective-C bridge files.
- Release docs and release metadata.

## Future Phases

Later refactor phases can build on this split:

- Move concrete read-loop and display-loop application code into runner objects
  if the first state-helper split leaves `IRFFDecoder` too large.
- Review `IRFFAudioDecoder` and `IRFFVideoDecoder` hot loops after decoder
  orchestration has clearer boundaries.
- Consider operation lifecycle ownership extraction after read/display loop
  behavior has focused coverage.
