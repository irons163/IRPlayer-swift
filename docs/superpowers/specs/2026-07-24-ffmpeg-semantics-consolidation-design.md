# FFmpeg Semantics Consolidation Design

Date: 2026-07-24

## Context

The remaining FFmpeg policy inventory contains seven files and eight policy
types:

- `IRFFAudioDecoderPolicy`
- `IRFFDecoderAudioPolicy`
- `IRFFDecoderBufferingPolicy`
- `IRFFDecoderDisplayPolicy`
- `IRFFDecoderPacketPolicy`
- `IRFFErrorPolicy`
- `IRFFStreamTimingPolicy`
- `IRFFVideoDecoderPolicy`

Audio, video, and coordinating decoder types expose wrapper methods that only
forward to these policies. Read/display loop state types bypass the decoder
owner and call the same policies directly. Tests therefore divide behavior
between policy-only suites and wrapper-equality checks.

The audit also found two unsafe malformed-input boundaries: packet routing
narrows arbitrary `Int` track indexes to `Int32` with a trapping conversion,
and display clock calculations can accept non-finite positions or a
finite-input derived overflow.

## Goals

- Put audio decode arithmetic and frame admission on `IRFFAudioDecoder`.
- Put video timing, backpressure, and frame admission on `IRFFVideoDecoder`.
- Put coordinating audio, buffering, packet, and display transitions on
  `IRFFDecoder`.
- Make read/display loop states consume decoder-owned semantics.
- Keep shared FFmpeg send/receive result classification in one named value
  semantic rather than duplicate it between audio and video.
- Put error translation and stream timing directly at the `IRFFTools`
  function boundary.
- Replace trapping numeric narrowing with exact conversion.
- Reject non-finite and overflowing derived clock/timing values
  deterministically.
- Remove all seven policy files and every mirror-only test.
- Preserve decode resource ownership, queue lifecycles, public behavior, and
  real audio/video integration.

## Non-Goals

- Changing FFmpeg C resource allocation or ownership.
- Changing format-context, decoder-session, collaborator, frame queue, or
  packet queue lifecycles.
- Changing codec selection, resampler setup, pixel formats, or audio sample
  representation.
- Rewriting the read or display loops.
- Consolidating RenderKit policies in this slice.

## Design

### Shared decode-result value

`IRFFDecodeResult` classifies FFmpeg send/receive results. Non-negative results,
`EAGAIN`, and FFmpeg EOF are non-failures; every other negative result is a
failure. Audio and video decoders consume this value semantic directly.

### Audio decoder ownership

`IRFFAudioDecoder` directly owns:

- sample element and byte-count checked arithmetic;
- fallback duration and decoded duration;
- input/output resampler metadata validation;
- resample ratio and capacity checked arithmetic;
- packet/frame data admission and direct-output format selection.

Every derived floating-point value is checked before integer conversion or
publication.

### Video decoder ownership

`IRFFVideoDecoder` directly owns:

- tick/repeat-picture and FPS fallback duration;
- decode backpressure and idle decisions;
- end-of-file completion;
- YUV-frame plane admission;
- packet queue fallback duration.

Derived tick and repeat durations must remain finite and positive.

### Coordinating decoder ownership

`IRFFDecoder` directly owns:

- audio packet error translation;
- buffered-duration and buffering-status transitions;
- audio dequeue admission;
- packet backpressure, EOF transitions, and routing;
- audio-synchronized and standalone display timing;
- frame ordering, idle display timing, and display completion.

Buffering transitions reject malformed clocks without publishing invalid start
times. Packet routing converts optional track indexes with `Int32(exactly:)`;
unrepresentable indexes are treated as non-matches.

Display timing requires finite frame/audio clocks, validates any derived frame
end, and never publishes a non-finite or non-positive sleep interval.

### Loop state consumers

`IRFFDecoderReadLoopState` and `IRFFDecoderDisplayLoopState` continue to map
decoder decisions into typed loop actions, but call `IRFFDecoder` instead of a
parallel policy implementation.

### Tool boundary

`IRFFCheckErrorCode`, `IRFFFinitePositiveValueOrDefault`,
`IRFFStreamGetTimebase`, and `IRFFStreamGetFPS` implement their semantics
directly. Error strings remain generated with `av_strerror`; stream rational
fallback precedence remains average rate, real rate, inverse timebase, then
one.

## Test Strategy

- Remove audio/video wrapper-equality tests while retaining direct owner and
  real decode integration tests.
- Rename decoder audio, display, and packet policy suites to owner-semantic
  suites and call `IRFFDecoder`.
- Add malformed buffering-clock and derived elapsed-overflow cases.
- Add exact packet-route tests for `Int32.min`, `Int32.max`, `Int.min`, and
  `Int.max`.
- Add display non-finite clock and finite-input frame-end overflow cases.
- Add audio/video derived duration and ratio/capacity boundary tests.
- Replace tool policy mirrors with exact error and stream fallback assertions.
- Run focused decoder/tool/loop suites, affected decode boundaries under Thread
  Sanitizer, the full iOS Simulator suite, and a generic iOS Release build.

## Acceptance Criteria

- No source, test, or Xcode project reference to any deleted FFmpeg policy
  remains.
- Read/display loops use decoder-owned semantics.
- Audio and video share one explicit decode-result value.
- Arbitrary track indexes cannot trap packet routing.
- Invalid clocks and derived timing overflow never publish a sleep or buffering
  timestamp.
- The source tree policy count falls from 17 to 10.
- Focused, Thread Sanitizer, full-suite, Release, project, warning, and
  whitespace gates pass.
