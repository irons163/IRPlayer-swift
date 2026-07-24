# RGB Frame Generation and Video Geometry Design

## Summary

`IRVideoFrameRGB` currently has no complete content generation. Its byte
storage and line size are immutable, but width and height are inherited
independent mutable fields that callers assign later. Consumers can therefore
observe a new width with an old height or pixel payload.

The format contract is also contradictory: the UIKit fallback treats the
payload as 24-bit RGB, while Metal requires exactly four bytes per pixel and
uploads the same bytes as BGRA. A valid frame for one path is invalid or
misinterpreted by the other.

Replace this with:

- one atomic video-dimension value in the base frame;
- type-owned dimension snapshots for Core Video, I420, and RGB frames;
- an immutable, checked RGB frame generation with an explicit `rgb24` or
  `bgra32` format;
- a canonical four-channel Metal upload prepared at construction; and
- consumers that read one dimension or content snapshot rather than separate
  mutable properties.

## Problems

- `width` and `height` are public independently mutable stored properties.
- Render submission, programs, mesh construction, and scaling frequently read
  width and height separately.
- `IRVideoFrameRGB(linesize:rgb:)` cannot validate its bytes because dimensions
  arrive after construction.
- RGB fallback image creation accepts RGB24 while Metal accepts BGRA32 under
  the same untyped API.
- RGB image creation does not prove that the payload covers every declared row.
- A pooled software-YUV frame keeps an active plane generation when generic
  frame reuse clears only transport metadata.
- `IRVideoFrameRGBPolicy` and the RGB portion of
  `IRMetalRendererPixelFormatPolicy` forward semantics away from the frame that
  owns them.

## Goals

- Publish video dimensions as one immutable, equatable, sendable value.
- Make generic dimension replacement atomic and reject negative or half-empty
  dimensions.
- Let Core Video dimensions come directly from the retained pixel buffer.
- Let I420 dimensions come from the same locked plane generation as its bytes.
- Revoke I420 content when a pooled frame is prepared for reuse.
- Require RGB width, height, format, stride, and data in one failable
  initializer.
- Support explicit RGB24 and premultiplied BGRA32 inputs.
- Validate all row and total-byte arithmetic with overflow checks.
- Preserve padded source rows.
- Precompute a tightly packed RGBA8 upload for RGB24 and upload BGRA32 without
  changing channel order.
- Use the same immutable RGB snapshot for UIKit and Metal.
- Remove the two forwarding policy boundaries.
- Document the intentional 2.0 RGB construction migration.

## Non-Goals

- Change decoded NV12, BGRA Core Video, or I420 color conversion.
- Add a cross-command Metal texture cache.
- Add mutable RGB frame reuse.
- Change FFmpeg packet, queue, timing, or playback behavior.
- Infer a pixel format from stride; ambiguous inputs must state their format.
- Change shader color conversion or render-mode geometry.

## Components

### `IRFFVideoDimensions`

The value contains width and height. Valid states are:

- both dimensions positive; or
- both zero for an empty generic frame.

Negative and half-empty pairs are rejected.

`IRFFVideoFrame` stores its generic dimensions behind one lock and exposes
`setDimensions(width:height:)` for atomic replacement. Public width and height
become read-only compatibility projections. Internal consumers use
`dimensionSnapshot()`.

Frame subclasses override the snapshot source:

- `IRFFCVYUVVideoFrame`: retained `CVPixelBuffer`;
- `IRFFAVYUVVideoFrame`: the active locked I420 generation; and
- `IRVideoFrameRGB`: its immutable RGB generation.

### `IRRGBPixelFormat`

The public format is explicit:

- `rgb24`: three bytes per pixel in red, green, blue order;
- `bgra32`: four bytes per pixel in blue, green, red, premultiplied-alpha
  order.

No format is guessed from `bytesPerRow`.

### `IRRGBFrameGeneration`

Construction validates:

- positive dimensions;
- a positive stride covering the minimum bytes per row;
- checked stride-by-height byte count; and
- enough input bytes for every declared row.

The generation stores an exact source prefix and immutable diagnostics. RGB24
is converted once into tightly packed RGBA8 bytes for Metal. BGRA32 retains its
validated rows as the Metal upload. No pointer escapes either conversion or
upload scope.

### Consumer Integration

- UIKit image creation selects matching bit depth and bitmap information from
  the explicit format.
- Metal selects `.rgba8Unorm` for RGB24 and `.bgra8Unorm` for BGRA32.
- Frame submission, 2D programs, fisheye programs, scale calculations, and
  mesh fallback sizing read one dimension snapshot per operation.
- Per-command texture-generation reuse remains unchanged.

## Public 2.0 Migration

Before:

```swift
let frame = IRVideoFrameRGB(linesize: UInt(bytesPerRow), rgb: bytes)
frame.width = width
frame.height = height
```

After:

```swift
let frame = IRVideoFrameRGB(
    width: width,
    height: height,
    pixelFormat: .bgra32,
    bytesPerRow: bytesPerRow,
    data: bytes
)
```

Generic custom frames use:

```swift
frame.setDimensions(width: width, height: height)
```

## Invariants

- A dimension snapshot never contains one zero dimension and one positive
  dimension.
- Internal consumers never assemble a size from separate mutable reads.
- An RGB frame is either completely valid at initialization or does not exist.
- RGB payload format is explicit and identical across UIKit and Metal paths.
- Every source row is covered by validated immutable storage.
- RGB24 Metal bytes are exactly RGBA8 with alpha 255.
- BGRA32 Metal bytes preserve input byte order and row stride.
- RGB dimensions cannot diverge from its generation after publication.
- Preparing a pooled I420 frame for reuse revokes its active plane generation.

## Testing

- Dimension value validation and generic atomic replacement.
- Concurrent alternating dimension updates with no torn snapshots.
- Core Video and I420 type-owned dimensions.
- I420 pool-reuse revocation with capacity preservation.
- RGB invalid dimensions, stride, overflow, and short payload rejection.
- Padded RGB24 and BGRA32 rows.
- Exact RGB24-to-RGBA8 conversion.
- Stable immutable snapshots and rejected post-publication dimension changes.
- RGB24 and BGRA32 UIKit images.
- RGB24 and BGRA32 Metal texture bytes and formats.
- Render submission, 2D, fisheye, multi-view, fallback-image, and texture
  generation integration.

## Acceptance Criteria

- No source or test constructs an RGB frame and mutates dimensions afterward.
- No first-party render consumer reads frame width and height separately.
- The old ambiguous RGB initializer and both forwarding policies are removed.
- Focused tests, Thread Sanitizer, render integration, the full simulator
  suite, and a generic iOS device build pass.
