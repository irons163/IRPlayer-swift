# FFmpeg Packet Ownership Design

## Summary

Decoded input packets currently cross the format-reader, audio decoder, video
queue, and video decoder as copied `AVPacket` structs. Those copies share
FFmpeg reference-counted storage without expressing which copy must call
`av_packet_unref`. The video queue also represents flush with a fabricated
packet whose `data` points at a local stack value.

Replace this with one non-copyable `IRFFPacket` owner per successful read and a
typed video-queue item. Packet storage remains borrowed only while a scoped
consumer runs, and teardown always unrefs exactly once.

## Problems

- Copying `AVPacket` copies its pointers but does not retain the referenced
  buffers.
- The reader does not visibly transfer or release packet ownership on every
  routing branch.
- The audio decoder unrefs a local struct copy, while the reader retains an
  aliased struct value.
- The video queue stores a struct copy across threads and manually unrefs it
  during dequeue or flush.
- Ignored packets have no explicit cleanup path.
- The flush sentinel stores a `data` pointer derived from the address of a
  local packet value and later compares that dangling address.
- Queue destroy returns another magic `AVPacket` value with a negative stream
  index.
- Packet accounting tests cover numbers but not reference ownership,
  transfer, or exactly-once release.

## Goals

- Give each successfully read FFmpeg packet one non-copyable Swift owner.
- Move a pre-existing packet reference into the owner without retaining or
  duplicating it.
- Fill an empty owner once through a fixed-result mutable borrow.
- Scope raw `AVPacket` access while keeping the owner alive.
- Release the FFmpeg reference exactly once on close or deinitialization.
- Make close idempotent and safe against a concurrent scoped borrow.
- Transfer the owner explicitly into the video queue.
- Consume and close audio packets synchronously.
- Release ignored, failed, rejected, queued, and destroyed packets
  deterministically.
- Represent video data, flush, and closed queue states as enum cases.
- Remove the fabricated flush packet and negative-stream-index sentinel.
- Consolidate packet accounting beside the owning queue.

## Non-Goals

- Change FFmpeg demuxing, stream selection, decode ordering, or backpressure.
- Change the public custom-video data-source callbacks in this slice.
- Refactor decoder `AVFrame`, resampler, or codec-context ownership.
- Change packet timing fallback values.
- Change VideoToolbox packet payload conversion.

## Components

### `IRFFPacket`

`IRFFPacket` is a final owner with empty, ready, and closed phases.

- `init()` creates empty storage for one format read.
- `init(consuming:)` moves an existing packet reference and clears the source.
- `fill` permits one fixed-result mutation while empty and publishes ready
  state only for a nonnegative FFmpeg result.
- `snapshot` exposes immutable routing and accounting fields.
- `withPacket` provides a fixed-result borrowed value while holding the
  lifecycle gate.
- `close()` calls `av_packet_unref` once and is repeatable.
- `deinit` calls `close()`.

An injectable runtime records move and unref calls in ownership tests without
requiring the test target to link FFmpeg C symbols directly.

### Typed Video Queue Items

The video queue stores:

- `.packet(IRFFPacket)` for owned payloads;
- `.flush` for codec reset;
- `.closed` when a blocked consumer is released by destroy.

Only packet items contribute byte and duration accounting. Flush and closed
items carry no fake FFmpeg state.

### Reader And Decoders

The reader creates one empty owner for each read attempt. Routing either
transfers that owner to the video queue, consumes it in the audio decoder, or
lets deterministic cleanup release it.

The audio decoder closes its consumed owner on every exit path. The video
decode thread closes each dequeued packet after its scoped decode finishes.

## Invariants

- No ready FFmpeg packet reference has more than one owner.
- Moving a raw packet into an owner leaves the source empty.
- A ready owner is unreferenced exactly once.
- Raw packet access cannot overlap owner close.
- Every reader routing branch ends in transfer or release.
- Queued packet owners survive until decode, flush, or destroy.
- No control signal is encoded in `AVPacket.data` or `stream_index`.
- Queue accounting is derived from immutable owner snapshots.

## Testing

- Empty, ready, and closed owner phases.
- Move clears the source and close releases exactly once.
- Failed fill releases partial state and never publishes ready state.
- Concurrent close elects one cleanup owner.
- Scoped borrow delays close until the consumer returns.
- Queue FIFO, accounting, flush, destroy, and rejected-post-destroy cleanup.
- Typed flush and closed behavior with no packet sentinel.
- Audio invalid-packet and real PCM decode consumption.
- Video source, FFmpeg software, and VideoToolbox packet consumption.
- Reader ignored/audio/video routing and teardown integration.

## Acceptance Criteria

- The read loop no longer routes copied raw `AVPacket` values.
- `IRFFPacketQueue` stores owners rather than raw packet structs.
- Audio and video packet teardown is automatic and exactly once.
- `IRFFVideoDecoder.flushPacket` and `makeFlushPacket()` are removed.
- `IRFFPacketQueuePolicy.swift` is removed.
- First-party packet unref calls are centralized in the packet owner and
  explicit raw-format test compatibility helper.
- Focused tests, Thread Sanitizer, decoder/FFPlayer integration tests, the full
  simulator suite, and a generic iOS device build pass.
