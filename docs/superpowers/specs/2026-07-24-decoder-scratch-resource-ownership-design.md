# Decoder Scratch Resource Ownership Design

## Summary

The audio and video decoders still store raw decode scratch resources directly.
Both allocate an `AVFrame`; audio additionally stores a `SwrContext`, a
`realloc`-managed output buffer, and its size. Cleanup is deferred to decoder
deinitialization, partial resampler setup has manual branches, and video frees
its frame with generic `av_free` instead of `av_frame_free`.

Introduce focused RAII owners for the shared decode frame and audio resampler
generation. Keep raw addresses inside scoped borrows, use Swift-managed reusable
sample storage, and make all partial setup and teardown exact.

## Problems

- `IRFFAudioDecoder` owns four related resource fields with independent nil
  states.
- Resampler allocation, initialization, scratch growth, and cleanup are spread
  across setup, decode, and deinit.
- `realloc` failure handling must preserve the old allocation and size
  manually.
- Raw resample storage escapes into decoder logic as an untyped pointer.
- `IRFFVideoDecoder` calls `av_free` for an `AVFrame` allocated by
  `av_frame_alloc`; FFmpeg requires `av_frame_free`.
- Neither decoder can directly test allocation failure, initialization
  failure, exact cleanup, or close/borrow ordering.
- Decoder tests mostly assert forwarding-policy equivalence and output
  behavior, not C-resource ownership.

## Goals

- Pair every `av_frame_alloc` with exactly one `av_frame_free`.
- Share one focused frame-owner implementation between audio and video.
- Prevent frame close from overlapping a decode-frame borrow.
- Give each initialized `SwrContext` one non-copyable owner.
- Free partially allocated resampler contexts on every setup failure.
- Replace `realloc` scratch memory with reusable Swift-managed `Int16` storage.
- Keep scratch addresses inside one fixed-result conversion operation.
- Validate byte/sample counts with checked arithmetic before publishing output.
- Make close repeatable and deinit-safe.
- Inject allocation, initialization, conversion, and cleanup operations for
  deterministic failure-path tests.
- Preserve audio/video timing, queues, decode routing, and public callbacks.

## Non-Goals

- Change codec-context ownership; it remains in the format-context generation.
- Change packet ownership, which is handled by `IRFFPacket`.
- Change audio output sample format from packed signed 16-bit conversion.
- Change video frame-plane publication or VideoToolbox session ownership.
- Redesign decoder worker scheduling.
- Consolidate all audio/video decision policies in this slice.

## Components

### `IRFFDecodeFrame`

A final owner allocates one `AVFrame`.

- Construction fails when `av_frame_alloc` fails.
- `withFrame` provides a fixed-result scoped pointer while holding the
  lifecycle gate.
- `close()` waits for an active borrow, calls `av_frame_free` once, and is
  repeatable.
- `deinit` calls `close()`.
- Diagnostics expose closed and frame-availability state without exposing the
  pointer.

An injected runtime provides allocation and free operations for exact
ownership tests.

### `IRFFAudioResampleSession`

A final owner publishes one initialized resampler generation containing:

- one `SwrContext`;
- fixed input/output rate, layout, format, and channel counts;
- reusable Swift `[Int16]` output scratch storage.

Construction performs allocation and initialization locally. Any nonnil
context produced on a failure path is freed before construction fails.
The generation identity includes FFmpeg's reconstructible channel-layout
description, so equal channel counts with different ordering or masks cannot
reuse an incompatible resampler. The borrowed codec layout is deep-copied with
`av_channel_layout_copy` before it is passed to swresample.

`withConvertedSamples`:

- validates output capacity and FFmpeg buffer size;
- grows managed sample storage only on the decoder thread;
- invokes `swr_convert` while storage is scoped;
- checks returned frame and sample counts;
- lends an immutable `Int16` buffer to one fixed-`Bool` consumer;
- returns a typed conversion outcome.

Close waits for conversion, frees the context exactly once, releases scratch
storage, and becomes terminal.

### Decoder Integration

Audio and video decoders hold optional frame owners instead of raw frame
pointers. A missing frame owner makes decode unavailable without passing nil
into FFmpeg.

Audio uses the resampler owner when setup succeeds. Direct S16 input remains a
scoped fallback. Both paths populate `IRFFAudioFrame` through the same checked
sample conversion helper.

## Invariants

- Every allocated decode frame has one owner and one matching
  `av_frame_free`.
- Frame and resampler pointers never outlive their scoped owner operation.
- Close cannot overlap frame receive or sample conversion.
- A resampler is published only after successful allocation and
  initialization.
- Partial resampler setup cannot leak a context.
- Scratch sample storage has one Swift owner and no manual
  `malloc`/`realloc`/`free`.
- A successful conversion cannot publish more samples than allocated.
- Failed audio-frame population returns the pooled frame to the pool.

## Testing

- Frame allocation failure and successful diagnostics.
- Frame scoped borrow, concurrent close ordering, repeatable close, and deinit.
- Resampler allocation and initialization failure cleanup.
- Same-count but different channel layouts create distinct generations.
- Conversion FFmpeg errors, invalid sizes, and consumer rejection.
- Managed sample capacity growth and reuse.
- Resampler concurrent close ordering and exact cleanup.
- Audio invalid packet and real PCM decode.
- Video queue/source behavior and real software decode.
- Decoder session close and FFPlayer integration.

## Acceptance Criteria

- Audio/video decoders store no raw `AVFrame` fields.
- `IRFFVideoDecoder` no longer calls `av_free` for its decode frame.
- Audio decoder stores no raw `SwrContext`, scratch pointer, or scratch size.
- First-party decoder code contains no resample `realloc`/`free`.
- Frame and resampler owners have deterministic failure and concurrency tests.
- Focused tests, Thread Sanitizer, decoder/FFPlayer integration tests, the full
  simulator suite, and a generic iOS device build pass.
