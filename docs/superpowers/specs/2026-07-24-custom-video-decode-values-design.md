# Custom Video Decode Value Boundary Design

## Summary

`IRFFVideoInput` is documented as supporting asynchronous custom decoding, but
its callback currently receives an `AVPacket` value whose payload and side-data
pointers are borrowed only for the duration of the synchronous decoder call.
The same callback also receives a publicly mutable
`UnsafeMutablePointer<AVCodecContext>` owned by the format-context generation.
Either pointer can escape into the asynchronous work shown by the public
example and become dangling or mutate decoder-owned state.

Replace both borrowed FFmpeg surfaces with complete immutable Swift values:

- an `IRFFVideoCodecDescriptor` copied from the active codec context;
- an `IRFFCompressedVideoPacket` that owns payload, timing, flags, and copied
  side data; and
- an immutable `IRFFVideoDecoderInfo` that combines the descriptor with the
  current decoder settings.

The built-in FFmpeg and VideoToolbox paths continue using scoped raw FFmpeg
values internally. Only the public custom-decode boundary changes.

## Problems

- `IRFFVideoDecoderInfo.codecContext` exposes a mutable pointer owned and later
  freed by `IRFFFormatContextGeneration`.
- Passing `AVPacket` by value does not copy its payload or side-data buffers.
- A custom source can retain either borrowed pointer after the callback.
- The README explicitly encourages dispatching custom decode work
  asynchronously without documenting the borrow lifetime.
- Codec extradata, dimensions, and format can be read independently while
  external code can mutate the same context.
- The forwarding-only `IRFFDecoderCodecContextPolicy` obscures a simple
  internal lookup and provides no ownership boundary.

## Goals

- Make every public custom-decode input safe to retain beyond the callback.
- Remove FFmpeg pointer types from `IRFFVideoDecoderInfo`.
- Copy codec identity, geometry, pixel format, profile, level, bitrate, and
  exact extradata into one immutable descriptor.
- Copy packet payload, optional timestamps, duration, stream index, flags,
  file position, and every side-data entry into one immutable packet.
- Preserve unknown codec and packet side-data identifiers through raw-value
  wrappers.
- Reject malformed codec geometry, extradata, packet sizes, or side-data
  layouts before calling a custom source.
- Construct one descriptor and packet snapshot per packet and pass the same
  values to both custom routing callbacks.
- Preserve synchronous custom frame returns and asynchronous
  `videoOutput.send(videoFrame:)`.
- Make the asynchronous output binding synchronized and non-owning, and make
  its routing mode immutable after input construction.
- Keep built-in software and VideoToolbox decode behavior unchanged.
- Remove `IRFFDecoderCodecContextPolicy`.
- Document the intentional 2.0 callback migration.

## Non-Goals

- Change FFmpeg packet ownership inside `IRFFPacket` or `IRFFPacketQueue`.
- Replace the built-in decoder's scoped `AVPacket` or codec-context calls.
- Add an asynchronous completion handler to `IRFFVideoInput`.
- Interpret codec-specific extradata or packet side data.
- Change packet timestamp units; raw ticks remain paired with decoder
  `timebase`.
- Change decoder backpressure, frame ordering, or error behavior.

## Components

### `IRFFVideoCodecIdentifier`

An immutable raw-value wrapper preserves all FFmpeg codec identifiers without
exposing the imported C enum. Well-known identifiers such as H.264, HEVC,
MPEG-4, and MJPEG are available as typed constants.

### `IRFFVideoCodecDescriptor`

The descriptor is constructed synchronously from one codec context and copies:

- codec identifier;
- coded width and height;
- pixel-format raw value;
- profile and level;
- bitrate; and
- exactly `extradata_size` bytes.

Dimensions must be both positive or both zero. A positive extradata size
requires a non-nil pointer; negative sizes fail construction.

### `IRFFCompressedVideoPacket`

Packet construction validates checked sizes and owns:

- exact payload bytes;
- optional PTS and DTS (`AV_NOPTS_VALUE` becomes `nil`);
- duration ticks;
- stream index;
- flags and derived key-frame state;
- source position; and
- ordered, immutable side-data entries with raw type identifiers.

A positive byte count requires a non-nil pointer. A positive side-data count
requires a side-data array, and each positive entry size requires data.
Construction is all-or-nothing.

### `IRFFVideoDecoderInfo`

The immutable info value combines one codec descriptor with the current
hardware-decoding flag, maximum decode duration, timebase, and frames per
second. It no longer provides any mutable pointer.

### Callback Integration

`IRFFVideoDecoder` builds the codec and packet values while the internal raw
packet borrow is active. If construction succeeds, both
`shouldHandle(_:decodeFrame:)` and `videoDecoder(_:decodeFrame:)` receive the
same values. Retaining or sending them to a `Task` is safe because all
FFmpeg-owned bytes have already been copied.

If a custom source declines the packet, the original borrowed `AVPacket`
continues through VideoToolbox or software FFmpeg decode within its existing
scope.

`IRFFVideoInput.videoOutput` is a lock-protected weak binding so asynchronous
custom work can read it while facade replacement clears or rebinds it without
a race or stale ownership. `outputType` is fixed at initialization.

## Public 2.0 Migration

Before:

```swift
override func videoDecoder(
    _ decoder: IRFFVideoDecoderInfo,
    decodeFrame packet: AVPacket
) -> IRFFVideoFrame? {
    decodeLater(packet.data, codec: decoder.codecContext)
    return nil
}
```

After:

```swift
override func videoDecoder(
    _ decoder: IRFFVideoDecoderInfo,
    decodeFrame packet: IRFFCompressedVideoPacket
) -> IRFFVideoFrame? {
    Task {
        await decode(packet.data, codec: decoder.codec)
    }
    return nil
}
```

## Invariants

- No public custom-decode value contains an FFmpeg pointer.
- Packet and codec bytes remain valid after the callback and after internal
  packet/context teardown.
- Codec geometry is never negative or half-empty.
- Positive declared byte counts always have backing storage.
- Packet side-data order and raw identifiers are preserved.
- Both custom routing callbacks observe the same immutable generation.
- Declining custom handling leaves the internal built-in decode path
  unchanged.
- Output binding replacement is synchronized and the input never owns its
  display or decoder target.

## Testing

- Codec descriptor copying, validation, identifiers, and caller mutation.
- Packet payload, timestamp, flag, position, side-data, and malformed-input
  behavior.
- Captured packet and codec values surviving source-memory mutation and packet
  close.
- Exact same info/packet values across both custom callbacks.
- Custom synchronous frame return and asynchronous output integration.
- Concurrent output reads/rebinding and weak target lifetime.
- Built-in software, VideoToolbox, decoder orchestration, queue, and player
  regressions.
- Thread Sanitizer coverage for custom callback capture and decoder teardown.

## Acceptance Criteria

- No public custom-decode API mentions `AVPacket`,
  `AVCodecContext`, or an unsafe pointer.
- No first-party callback can retain borrowed FFmpeg packet/context memory.
- Malformed values never reach a custom source.
- Existing built-in decode integration remains green.
- Focused tests, Thread Sanitizer, the full simulator suite, and a generic iOS
  device build pass.
