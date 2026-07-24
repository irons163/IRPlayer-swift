# Format Context Resource Ownership Design

## Summary

`IRFFFormatContext` currently publishes an `AVFormatContext`, video codec
context, audio codec context, track selection, metadata, timing, and setup
error as unrelated mutable properties while setup is still in progress. Its
FFmpeg interrupt callback receives an unretained pointer to the facade.
Successful codec contexts are closed with `avcodec_close` and then discarded,
even though the bundled FFmpeg headers require contexts returned by
`avcodec_alloc_context3` to be destroyed with `avcodec_free_context`.

This change makes the facade publish one complete resource generation after
input discovery and usable-track setup finish. All operations that consume or
replace FFmpeg pointers share one execution gate. The interrupt callback uses
a separately retained, synchronized state that can abort a blocking FFmpeg
operation before `destroy()` waits for the execution gate.

## Evidence

The bundled FFmpeg headers are the authoritative API contract for the shipped
binary:

- `avcodec_alloc_context3` says its result must be freed with
  `avcodec_free_context`.
- `avcodec_close` says not to use it to destroy a codec context because it does
  not free the `AVCodecContext` itself.
- `avformat_open_input` says a supplied format context is freed on failure.
- `avformat_close_input` closes and frees an opened input context and writes
  `nil` back to the pointer.

The current successful track-switch and teardown paths call `avcodec_close`,
set the pointer to `nil`, and therefore lose the only pointer that could free
the allocation.

## Problems

- Partially initialized FFmpeg resources are visible as independent fields.
- Setup, seek, read, track replacement, and destroy have no common operation
  boundary.
- The interrupt callback dereferences `Unmanaged.passUnretained(self)`.
- Direct destruction cannot signal a blocked FFmpeg call before waiting for
  exclusive access.
- Successful audio/video codec contexts are closed but never freed.
- Replacing an audio track leaks the old codec-context allocation.
- Repeated setup and use-after-destroy semantics are implicit.
- `IRFFFormatContextPolicy` duplicates the facade through one-to-one forwarding
  methods.
- Tests compare wrappers to their implementation instead of asserting one
  domain contract.

## Goals

- Model idle, opening, active, failed, closing, and closed phases.
- Build input, streams, codec contexts, metadata, tracks, and derived values
  locally and publish them as one complete generation.
- Serialize setup, seek, read, track replacement, track destruction, and final
  destruction.
- Make `destroy()` terminal, idempotent, and safe to call while an FFmpeg
  operation may be blocked.
- Retain callback state for exactly the lifetime of the matching opened input.
- Release callback state only after the input context is closed.
- Use `avcodec_free_context` for every allocated codec-context success and
  failure path.
- Preserve the existing rule that setup succeeds when at least one usable
  audio or video track opens.
- Preserve borrowed codec-context access for decoders while the outer decoder
  session owns their ordering.
- Consolidate pure format, timing, track, and selection semantics beside the
  domain and remove `IRFFFormatContextPolicy`.
- Add deterministic lifecycle, callback, real-file, and concurrency tests.

## Non-Goals

- Change FFmpeg demuxing, decoder selection, RTSP transport, or stream-choice
  heuristics.
- Add subtitle decoding.
- Change packet routing or seek behavior.
- Let an `IRFFFormatContext` reopen after terminal destruction.
- Move ownership of codec contexts into audio/video decoders.
- Change the public `IRFFFormatContextDelegate` protocol.

## Components

### `IRFFFormatContext`

The facade owns:

- immutable content URL and requested video format;
- one operation gate;
- one lifecycle phase and optional complete generation;
- one interrupt state shared with the current generation;
- the latest setup error.

Every getter reads a coherent active-generation snapshot under the operation
gate. Raw codec pointers remain borrowed and are valid only while the facade
generation is active.

### `IRFFFormatContext.Generation`

One generation owns:

- the opened `AVFormatContext`;
- optional opened video and audio `AVCodecContext` values;
- the retained interrupt callback reference;
- metadata and discovered tracks;
- selected tracks and their derived timing/presentation values.

Construction may mutate a private local generation, but it is not published
until setup has a usable track. Teardown frees codec contexts, closes the input
context, and then releases the callback reference. Teardown is idempotent.

### `IRFFFormatContextInterruptState`

The callback state stores weak facade/delegate references and a forced
interrupt flag under its own lock. `destroy()` first sets the forced flag, then
waits for the facade operation gate. This allows a blocking `avformat_open_input`,
`avformat_find_stream_info`, or `av_read_frame` call to return.

The FFmpeg `opaque` value is created with `Unmanaged.passRetained` for each
opened-input attempt. The callback dereferences the interrupt state, never the
facade. Once the input is closed, the generation releases that retained
reference.

### Format Semantics

Duration, bitrate, presentation size, setup-error selection, seek timestamps,
track creation, aspect ratio, and audio-selection admission remain pure
functions on the `IRFFFormatContext` domain. The separate forwarding policy
type is removed.

## Lifecycle

```text
idle --setup--> opening --publish--> active
                      \--error----> failed

idle/opening/active/failed --destroy--> closing --> closed
```

- Setup is admitted only from idle.
- A successful generation is published atomically.
- A failed setup owns no generation and exposes one setup error.
- Repeated setup after active, failed, or closed is a no-op.
- Destroy requests interruption before waiting for exclusive access.
- Closed is terminal and all resource getters return their empty defaults.

## Track Replacement

Audio-track replacement first opens a complete candidate codec context. Only
after that succeeds does the generation swap selected-track state and free the
old context with `avcodec_free_context`. A failed candidate leaves the current
generation unchanged.

## Testing

- Pure semantics tests assert the domain directly; wrapper-equivalence tests
  are removed.
- Interrupt-state tests cover delegate decisions, forced interruption,
  concurrent reads/updates, and safe behavior after the facade disappears.
- Lifecycle tests cover failed setup, successful real-file setup, duplicate
  setup, idempotent terminal destroy, and empty closed diagnostics.
- Real-file tests verify borrowed context publication and packet reads while
  active.
- Concurrent read/getter/destroy stress runs under Thread Sanitizer.
- Decoder integration tests verify the outer owner still destroys decoders
  before the format generation.

## Acceptance Criteria

- No successful path discards a codec context without
  `avcodec_free_context`.
- The FFmpeg interrupt callback never dereferences an unretained
  `IRFFFormatContext`.
- Only complete generations are visible.
- Setup/read/seek/replace/destroy share one operation boundary.
- Destroy can request interruption before waiting for that boundary.
- Input teardown closes the format context before releasing callback state.
- Destroy is idempotent and closed is terminal.
- `IRFFFormatContextPolicy.swift` is removed.
- Focused tests, Thread Sanitizer, integration tests, the full simulator suite,
  and a generic iOS device build pass.
