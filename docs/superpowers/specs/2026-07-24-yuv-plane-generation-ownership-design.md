# YUV Plane Generation Ownership Design

## Summary

`IRFFAVYUVVideoFrame` currently owns its luma, chroma-B, and chroma-R planes
through three independently allocated `malloc` buffers. Their mutable pointers
are exposed to the Metal renderer and tests, while plane dimensions, lengths,
capacities, line sizes, pixel format, and image cache are stored separately.

Replace that representation with one checked, Swift-managed I420 plane
generation. A frame publishes all plane bytes and metadata atomically. Readers
receive a copy-on-write snapshot, and raw addresses exist only while a snapshot
is inside a scoped operation.

## Problems

- Three manual `malloc`/`free` pairs must remain synchronized with three
  capacity and active-length arrays.
- Public mutable plane pointers can escape the frame and outlive buffer growth,
  reuse, or destruction.
- Width, height, pixel format, line sizes, lengths, and pointers can describe
  different frame generations.
- The renderer reads plane pointers and dimensions separately.
- `image()` converts directly from mutable frame buffers and uses a cache that
  is not generation-tagged.
- Source line sizes are only required to be positive. A line shorter than the
  destination texture width can publish an undersized plane that Metal later
  reads as tightly packed full-width rows.
- Chroma dimensions use floor division even though 4:2:0 odd dimensions require
  ceiling division.
- `IRFFAVYUVVideoFramePolicy` and `IRYUVChannelFilterPolicy` are forwarding-only
  layers around decisions that belong to the plane domain.

## Goals

- Own every software-decoded I420 plane through Swift arrays.
- Validate dimensions, source line sizes, checked byte counts, and all three
  source pointers before publication.
- Use ceiling chroma dimensions for odd I420 sizes.
- Build and publish luma/chroma bytes plus metadata as one generation.
- Preserve reusable capacity across frame-pool reuse.
- Return copy-on-write snapshots that survive later frame updates.
- Scope all raw plane addresses to image conversion or synchronous Metal
  texture upload.
- Make flush revoke active data and cached images without exposing stale bytes.
- Tag the image cache with the exact plane generation.
- Remove the two frame-local forwarding policies and their equivalence tests.
- Add invalid-layout, reuse, snapshot, rendering, image, and concurrency tests.

## Non-Goals

- Change hardware-decoded `CVPixelBuffer` ownership.
- Change shader color conversion, texture filtering, or render-mode selection.
- Add support for new planar pixel formats in this slice.
- Change FFmpeg packet/frame queue ordering.
- Refactor the base frame playing-state lifecycle.
- Remove the broader `IRYUVToolsPolicy` in the same commit.

## Components

### `IRYUVPlaneLayout`

A checked value describes one source plane:

- destination width and height;
- source line size;
- tightly packed destination row-byte count;
- total active byte count.

Construction rejects non-positive dimensions, a source line shorter than the
plane width, `Int32` conversion failures, and multiplication overflow. Copying
grows managed storage only when needed, then copies each active source row into
the tightly packed destination.

### `IRFFYUVPlaneStorage`

The mutable storage value owns three `[UInt8]` buffers and their active counts.
Its array counts represent reusable capacity. Updating writes all three planes
before the frame publishes their metadata. Deactivation clears active counts
but keeps capacity.

Because snapshots share standard Swift arrays, a later mutation uses
copy-on-write when an older snapshot is still alive. No custom reference
counting or manual allocation is required.

### `IRFFYUVPlaneSnapshot`

The immutable value contains:

- generation number;
- luma and chroma dimensions;
- tightly packed line sizes;
- pixel format;
- active byte counts;
- copy-on-write plane arrays.

It exposes value-copy diagnostics for tests, a fixed-result scoped byte
operation for Metal, and an image conversion operation that does not return
plane pointers.

### `IRFFAVYUVVideoFrame`

The frame serializes update, flush, snapshot, and cache publication with one
lock. `setFrameData` validates the complete input before changing active
metadata, updates reusable managed storage, advances the generation, publishes
the new dimensions and size, and invalidates the image cache.

`planeSnapshot()` returns either one complete generation or no active data.
`image()` converts a snapshot outside the lock and caches the result only if the
frame still owns that same generation.

### Metal Renderer

The renderer requests one plane snapshot, creates all three textures within
that snapshot's scoped byte operation, then uses the resulting textures after
the raw addresses have expired. It never reads separate frame pointers or
dimensions.

## Invariants

- Active software YUV data always has exactly three valid I420 planes.
- Luma dimensions equal frame dimensions.
- Chroma dimensions equal ceiling(width / 2) and ceiling(height / 2).
- Every source line size is at least its plane width.
- Every active byte count equals checked tightly packed width multiplied by
  height and fits its managed buffer.
- Total frame size is the checked sum of all active plane byte counts.
- A snapshot's bytes and metadata all belong to one generation.
- A later update or flush cannot mutate an already returned snapshot.
- Flush publishes no active snapshot even though capacity may be retained.
- A cached image is returned only for its matching active generation.
- No frame-owned plane pointer is stored or returned.

## Testing

- Checked layouts reject invalid, undersized, and overflowing inputs.
- Odd I420 dimensions use ceiling chroma sizes.
- Valid padded source rows become tightly packed managed planes.
- Smaller frames reuse capacity without exposing inactive bytes.
- Larger frames grow capacity.
- Flush removes active snapshots while retaining reusable capacity.
- An old snapshot remains unchanged across later updates.
- Concurrent update, snapshot, and value-read stress passes Thread Sanitizer.
- Image caching is generation-bound.
- Metal creates and renders all three textures from managed snapshots.
- Real software FFmpeg decoding publishes coherent plane snapshots.

## Acceptance Criteria

- `IRFFAVYUVVideoFrame` stores no raw plane pointer and calls no
  `malloc`/`free`.
- Metal and image conversion do not read a frame-owned pointer outside a scoped
  snapshot operation.
- Invalid or partial inputs publish no active generation.
- Frame-pool reuse preserves managed capacity.
- `IRFFAVYUVVideoFramePolicy.swift` and
  `IRYUVChannelFilterPolicy.swift` are removed.
- Focused tests, Thread Sanitizer, decoder/render integration tests, the full
  simulator suite, and a generic iOS device build pass.
