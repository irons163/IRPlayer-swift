# YUV Image Conversion Resource Ownership Design

## Summary

Snapshot conversion still creates a raw `SwsContext` and an
`av_image_alloc` buffer inside one free function. Cleanup is repeated across
success and failure branches, output capacity is represented by parallel C
arrays, and the conversion semantics are split through a forwarding-only
`IRYUVToolsPolicy`.

Introduce a focused conversion-session owner. It will publish a fully
constructed scaling context with checked RGB24 geometry, keep reusable output
bytes in Swift-managed storage, lend those bytes only through a scoped
operation, and perform exact repeatable teardown.

## Problems

- `IRYUVConvertToImage` directly owns a raw `SwsContext`.
- The function allocates an FFmpeg image buffer and manually frees it on
  several branches.
- Context, data pointer, line size, and allocation result can temporarily
  describe a partial resource generation.
- Conversion accepts any nonnegative `sws_scale` result, including incomplete
  output.
- Raw output storage is passed between conversion and image creation without a
  typed capacity boundary.
- Allocation, scale, consumer, close, and deinitialization failure paths cannot
  be tested deterministically.
- `IRYUVToolsPolicy` contains the implementation while the established
  functions only forward to it.

## Goals

- Give every nonnil `SwsContext` one non-copyable owner.
- Publish a session only after context creation and output-storage allocation
  both succeed.
- Free a context when later construction fails.
- Replace `av_image_alloc` and `av_freep` with checked Swift-managed RGB24
  storage.
- Keep source and destination pointers inside one fixed-result scoped
  conversion.
- Require `sws_scale` to produce the complete requested height.
- Make close repeatable, terminal, and serialized with conversion.
- Inject context creation, scaling, storage allocation, and cleanup for exact
  failure-path tests.
- Preserve the existing YUV helper function signatures and snapshot behavior.
- Move pure YUV geometry and row-copy semantics beside their public helper
  functions and remove the forwarding-only policy file.

## Non-Goals

- Cache conversion sessions across immutable YUV snapshots.
- Change software-decoded plane ownership or Metal texture publication.
- Change the public snapshot API.
- Replace FFmpeg scaling with a custom color-conversion implementation.
- Change Core Graphics or `UIImage` creation semantics.
- Consolidate unrelated image, renderer, or controller policy files.

## Components

### `IRYUVImageConversionConfiguration`

An immutable value validates width and height against FFmpeg's signed 32-bit
boundary and computes RGB24 row and total byte counts with checked arithmetic.
Invalid, overflowing, or unrepresentable configurations are rejected before
resource creation.

### `IRYUVImageConversionSession`

A final owner contains:

- one configured `SwsContext`;
- one immutable conversion configuration;
- one reusable Swift `[UInt8]` RGB24 output allocation;
- one lifecycle lock shared by conversion and close.

Construction creates all resources locally. If output allocation fails after
context creation, the context is released before initialization returns nil.

`withConvertedRGB` validates source-plane arrays, scales into managed output
storage, requires the exact output height, and lends immutable bytes, row size,
width, and height to one fixed-`Bool` consumer. It returns a typed outcome for
invalid input, conversion failure, consumer rejection, closed state, or
success.

`close()` waits for an active conversion, releases the context exactly once,
clears managed storage, and becomes terminal. `deinit` calls `close()`.

### Live FFmpeg Runtime

The live runtime:

- creates a scaler from the requested source format to RGB24;
- normalizes FFmpeg source and destination pointer/line-size arrays to
  `AV_NUM_DATA_POINTERS`;
- calls `sws_scale` only while all Swift buffers are borrowed;
- releases the context with `sws_freeContext`.

Tests inject the same operations without calling raw FFmpeg symbols.

### Existing Helper Integration

`IRYUVConvertToImage` creates a short-lived conversion session and creates the
platform image inside the session's scoped RGB borrow. `CFDataCreate` retains a
copy before the session closes.

The existing size, dimension, source-validation, and channel-filter functions
retain their signatures but own their implementations directly.

## Invariants

- Every created scaling context is freed exactly once.
- A session is never observable with only part of its resources.
- Close cannot overlap scaling or RGB consumption.
- No FFmpeg-allocated image buffer remains in first-party code.
- RGB output capacity equals checked `rowByteCount * height`.
- A successful conversion reports exactly the requested output height.
- Source and output pointers do not escape their scoped calls.
- Failed construction, conversion, or image creation publishes no image.

## Testing

- Invalid and overflowing configuration rejection.
- Context-creation and output-allocation failure cleanup.
- Successful managed output publication and capacity reuse.
- Invalid source arrays, FFmpeg errors, and incomplete output.
- Consumer rejection and closed-session behavior.
- Concurrent conversion/close ordering.
- Repeatable close and deinitialization cleanup.
- Real RGB24 image creation.
- Existing software-YUV snapshot and Metal integration behavior.

## Acceptance Criteria

- `IRYUVConvertToImage` owns no raw FFmpeg resource directly.
- First-party code contains no `av_image_alloc` or `av_freep`.
- `sws_getCachedContext`, `sws_scale`, and `sws_freeContext` are isolated to the
  conversion-session runtime.
- Conversion storage is Swift-managed and scoped.
- `IRYUVToolsPolicy.swift` is removed without changing helper signatures.
- Focused tests, Thread Sanitizer, software-frame/render integration tests, the
  full simulator suite, and a generic iOS device build pass.
