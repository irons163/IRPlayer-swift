# Audio Frame Storage Ownership Design

## Summary

`IRFFAudioFrame` currently owns decoded PCM samples through an
`UnsafeMutablePointer<Float>`, a separate integer capacity, manual
allocation/reallocation, and deallocation in `deinit`. The pointer escapes the
frame into both the FFmpeg decoder and the real-time audio renderer.

This is unnecessary first-party unsafe ownership. Swift can own the contiguous
sample allocation while the two C-style consumers borrow a pointer only for the
duration of a closure. This change makes the frame the sole storage boundary,
keeps allocations out of the real-time render callback, and removes the
forwarding-only `IRFFAudioFramePolicy`.

## Problems

- The frame manually pairs allocation and deallocation across success, invalid
  length, growth, reuse, and deinitialization paths.
- `samples` is a freely escaping mutable pointer, so callers can retain it
  across storage replacement or frame reuse.
- Capacity, byte length, and pointer availability can become inconsistent.
- The FFmpeg decoder and renderer both understand frame storage layout instead
  of borrowing through one checked API.
- Tests assert pointer identity and facade-to-policy equivalence rather than
  the storage and real-time copy contract.
- `IRFFAudioFramePolicy` is a separate two-function forwarding layer with no
  independent domain.

## Goals

- Replace stored sample pointers with Swift-managed contiguous storage.
- Keep storage allocation and growth on the decoder side, never in the
  real-time render callback.
- Expose a mutable pointer only inside a fixed-result non-escaping borrow;
  expose reads through a value snapshot or checked copy.
- Expose one checked byte-copy operation for the renderer.
- Preserve byte-length, output-offset, frame-pool reuse, and PCM scaling
  semantics.
- Preserve capacity reuse when a later frame fits in the existing allocation.
- Clear storage and frame state deterministically for invalid byte lengths.
- Validate overflow, active byte bounds, and copy ranges before pointer use.
- Remove `IRFFAudioFramePolicy` and wrapper-equivalence tests.
- Add domain, renderer, decoder-integration, and concurrency regression tests.

## Non-Goals

- Change the output PCM format, interleaving, channel order, scale, sample
  rate, or duration calculation.
- Allocate or lock inside the Core Audio callback beyond the renderer's
  existing non-blocking admission lock.
- Change FFmpeg resampling behavior.
- Change frame-queue or frame-pool ordering.
- Refactor video-plane storage in the same commit.

## Components

### `IRFFAudioFrame`

The frame stores one `[Float]` whose count represents reusable capacity. `size`
continues to represent the active byte length and `outputOffset` continues to
represent the consumed byte offset.

`setSamplesLength(_:)`:

- rejects non-positive or overflowing lengths;
- rounds byte lengths up to enough `Float` elements;
- grows storage only when the current capacity is insufficient;
- retains existing capacity for equal or smaller valid frames;
- resets `outputOffset`;
- clears storage and active state for invalid input.

The frame exposes:

- a non-escaping, `Bool`-returning mutable sample borrow for decoder
  conversion and failure propagation;
- a value snapshot for inspection;
- a checked byte-copy method for real-time consumption;
- coherent active-sample and capacity diagnostics.

No method returns a stored pointer.

### FFmpeg Audio Decoder

The decoder requests frame storage, then performs `vDSP_vflt16` and
`vDSP_vsmul` within one mutable borrow. The pointer cannot outlive the frame's
current allocation.

### Real-Time Audio Renderer

The renderer retains its current frame as before. Its copy plan decides the
byte range, then the frame validates and copies that range to the Core Audio
output buffer. The callback performs no sample-storage allocation and never
retains the borrowed source address.

## Invariants

- Active byte length is positive only when sufficient contiguous storage
  exists.
- Capacity is measured in `Float` elements and cannot underflow the rounded-up
  active element count.
- Mutable borrows and value snapshots cover only active elements, not inactive
  retained capacity.
- A copy range is non-negative, non-overflowing, and entirely within active
  bytes.
- Invalid storage preparation leaves `size == 0`, `outputOffset == 0`, and zero
  capacity.
- Renderer copy planning remains frame-aligned.
- Frame-pool reuse can retain capacity without exposing a stale address.

## Testing

- Checked byte-to-element rounding and overflow.
- Invalid input clearing.
- Capacity reuse and growth without pointer-identity assertions.
- Mutable borrow bounds and written-value snapshots.
- Checked full, partial, and rejected byte copies.
- Renderer multi-callback and multi-frame behavior.
- Contended callback silence under Thread Sanitizer.
- Generated PCM16 decode and finite scaled sample output.
- FFPlayer audio-owner integration, full simulator suite, and device build.

## Acceptance Criteria

- `IRFFAudioFrame` stores no `UnsafeMutablePointer`.
- No first-party caller reads a frame-owned sample pointer outside a closure.
- The real-time renderer performs no sample allocation.
- Invalid and overflowing lengths cannot publish partial storage.
- Existing decoded-audio behavior remains green.
- `IRFFAudioFramePolicy.swift` is removed.
- Focused tests, Thread Sanitizer, audio/decoder/player integration tests, the
  full simulator suite, and a generic iOS device build pass.
