# Fish2Pano Managed Lookup Generation Design

## Summary

Fish2pano lookup work is generation-fenced, but the published value is still
an array of manually allocated mutable pointers. Ownership crosses from shader
params into render state through a `consume`/`release` protocol, metadata is
read separately from the buffers, and a caller can retain or index a pointer
outside the intended upload operation.

Replace that boundary with one immutable Swift-managed lookup generation. The
generation owns every UV array together with output geometry, antialias count,
texture count, element count, and request generation. Shader params atomically
publish or take the complete value. Render state reads bytes only through a
scoped buffer closure and lets normal ownership release the generation after
texture upload.

## Problems

- Lookup arrays use `UnsafeMutablePointer.allocate` and manual `deallocate`.
- The owner must keep a separate consumed-generation set until a matching
  pointer array is returned for release.
- Pointer identity is being used as an ownership token.
- Output width, output height, antialias, and buffers cross the boundary as
  separate reads rather than one coherent value.
- Texture upload receives a pointer without a length and cannot prove that the
  buffer covers the requested texture.
- The fish2pano policy file only forwards domain math and generation equality.

## Goals

- Store lookup values in Swift-managed copy-on-write arrays.
- Publish lookup bytes and all upload metadata as one immutable generation.
- Expose lookup storage only inside a scoped immutable buffer closure.
- Transfer a ready generation with one atomic take operation.
- Remove manual consumed-generation tracking and release pairing.
- Reject incomplete texture counts, element counts, invalid geometry, and
  metadata mismatches before Metal upload.
- Preserve latest-request-wins publication and all projection math.
- Move fish2pano lookup validation and indexing into the domain type and remove
  `IRGLFish2PanoShaderParamsPolicy`.
- Cover ownership, immutability, failure, stale work, texture upload, and
  concurrent publication with tests and Thread Sanitizer.

## Non-Goals

- Change fisheye projection equations or shader output.
- Change public player or render-mode APIs.
- Cache CPU lookup generations after successful Metal upload.
- Change Metal shader formats or the number of AA lookup textures.
- Consolidate unrelated program or renderer policies.

## Components

### `IRGLFish2PanoPixelMapGeneration`

A final immutable value owns:

- the request generation;
- output width and height;
- antialias and derived texture count;
- the exact UV element count for every texture;
- one Swift-managed `[GLfloat]` value per lookup texture.

Construction is failable and accepts only complete layouts. The source arrays
are copy-on-write values, so mutation by a builder or test after publication
cannot alter a retained generation. A scoped `withUnsafeMapBuffer` operation
validates the texture index and keeps storage borrowed only for the closure.

### Shader Params Publication

Pixel-map construction uses local mutable arrays. Only after every lookup
texture is populated are they moved into an immutable generation. Publication
holds the existing state lock and accepts the generation only when its request
number is still current.

`takePixelMapIfReady()` atomically removes and returns the published
generation. No mutable pointer leaves the owner and no matching release call is
required.

### Render-State Upload

Render state compares the generation's output size, antialias, texture count,
and element count with the requested configuration before replacing cached
Metal textures. Each upload executes within the generation's scoped buffer
closure and validates byte coverage.

Any invalid or incomplete generation is dropped without replacing a previous
complete texture set. A new output configuration still clears textures from
the incompatible old configuration.

## Invariants

- A published lookup generation is complete or unavailable.
- Lookup storage has no manual allocation or deallocation.
- No lookup pointer escapes a scoped immutable borrow.
- Metadata and bytes always describe the same generation.
- Only the newest requested generation can be published.
- Taking a generation removes it from shader params exactly once.
- Failed generation or texture construction never partially replaces the
  installed Metal texture set.
- Public player and render-mode behavior remains unchanged.

## Testing

- Complete generation construction and diagnostics.
- Invalid geometry, texture count, and per-texture element count rejection.
- Copy-on-write immutability after source mutation.
- Scoped buffer access, bounds, sentinel values, and calculated coordinates.
- Empty, take-once, latest-generation, and old-generation survival behavior.
- Metadata mismatch and partial Metal texture failure preserve the prior cache.
- Real Metal upload for every AA texture.
- Concurrent update, publication, take, and deinitialization under Thread
  Sanitizer.

## Acceptance Criteria

- No first-party fish2pano lookup path allocates, deallocates, returns, or
  accepts `UnsafeMutablePointer<GLfloat>`.
- `IRGLFish2PanoShaderParamsPolicy.swift` is removed.
- Shader params publish one immutable managed generation.
- Render state uploads only through scoped, length-aware immutable buffers.
- Focused, Thread Sanitizer, integration, full simulator, and generic iOS
  device validation pass.
