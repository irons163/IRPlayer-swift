# Metal Command Texture Lifetime Design

## Summary

Hardware-decoded NV12 and BGRA frames are converted from `CVPixelBuffer` into
`CVMetalTexture` references while an encoder is being populated. The renderer
currently extracts `MTLTexture` values and lets the Core Video wrappers leave
scope before the command buffer is committed. Core Video requires those
references to remain alive through command-buffer completion.

Introduce one immutable frame-texture generation per source frame and one
command-resource scope per command buffer. The generation keeps every Core
Video wrapper, source pixel buffer, and Metal texture coherent. The command
scope caches that generation across multi-view draws, transfers its retained
resources to a completion-owned generation before commit, and releases them
when the GPU signals completion.

## Problems

- `CVMetalTexture` references leave lexical scope immediately after encoder
  binding.
- The command buffer has no explicit owner for Core Video wrappers through GPU
  completion.
- Multi-view and distortion paths rebuild identical frame textures for every
  viewport or eye.
- Pixel format, plane textures, Core Video wrappers, and the source pixel
  buffer are represented as unrelated local values.
- Failed command construction and successful submission do not have explicit,
  testable resource-transfer semantics.
- Direct pixel-renderer tests cannot verify command-completion lifetime.

## Goals

- Keep every created `CVMetalTexture` alive until its submitted command buffer
  completes.
- Publish only complete NV12, BGRA, I420, or RGB frame-texture generations.
- Retain the source `CVPixelBuffer` with Core Video-backed generations.
- Create at most one texture generation per source-frame identity in one
  command scope.
- Reuse that generation across multi-view, fisheye-multi, and distortion-eye
  draws.
- Make collecting, submitted, and cancelled command-resource states explicit.
- Release unsubmitted resources immediately on cancellation or deinit.
- Move submitted resources to a completion-owned generation before commit.
- Reject resource collection or duplicate submission after the scope becomes
  terminal.
- Cover lifecycle and real Metal rendering behavior with focused tests and
  Thread Sanitizer.

## Non-Goals

- Change shader behavior, color conversion, texture formats, or render-mode
  output.
- Change public player, frame, or rendering APIs.
- Replace Core Video's Metal texture cache.
- Add cross-command texture caching.
- Change software I420 plane ownership.
- Consolidate unrelated renderer geometry, distortion, or scale policies.

## Components

### `IRMetalFrameTextureGeneration`

A final immutable generation contains:

- one typed texture layout (`nv12`, `bgra`, `i420`, or `rgb`);
- every `MTLTexture` required by that layout;
- all `CVMetalTexture` references used to create Core Video-backed textures;
- the source `CVPixelBuffer` for Core Video-backed layouts;
- immutable diagnostics describing format and retained resource counts.

Creation validates the source-frame type and pixel format, builds every
required plane locally, and returns nil unless the entire generation is
usable. Partial Core Video generations are never published.

### `IRMetalCommandResources`

A final synchronized scope starts in `collecting`. It caches one frame-texture
generation per `IRFFVideoFrame` identity and can retain additional command
resources.

Submission atomically moves the collected resources into a separate
completion-owned generation, changes the scope to `submitted`, and registers
one completion closure. The closure clears its resources exactly once when
the command buffer finishes.

Cancellation changes a collecting scope to `cancelled` and immediately drops
all cached resources. Submission and cancellation are terminal and repeatable
without double release.

### Renderer Integration

Every command-producing renderer entry point creates one command-resource
scope. Pixel renderers request their typed frame generation through that
scope, so repeated viewports and distortion eyes receive the same generation.

After successful encoding, the renderer submits the resource scope before
presenting and committing the command buffer. Failed rendering never commits
and lets the scope cancel on deinitialization.

## Invariants

- No `CVMetalTexture` used by submitted GPU work is released before completion.
- One command scope publishes at most one generation for a frame identity.
- A frame-texture generation is complete or unavailable.
- Core Video-backed generations retain their source pixel buffer.
- A command scope is collecting, submitted, or cancelled, never partially
  transferred.
- Submitted resources have exactly one completion owner.
- Completion, repeated cancellation, and deinitialization cannot double
  release resources.
- No cross-command cache can retain stale decoded frames.
- Render output and public APIs remain unchanged.

## Testing

- Complete NV12, BGRA, I420, and RGB generation creation.
- Invalid or unsupported source rejection.
- Typed plane count, dimensions, formats, and Core Video retention diagnostics.
- Same-frame generation reuse and different-frame separation.
- Construction failure is not cached.
- Collecting, submission, cancellation, duplicate-operation, and deinit
  behavior.
- Resource survival before completion and release after completion.
- Actual Metal command-buffer completion integration.
- Existing 2D, multi-view, fisheye, fish2pano, distortion, and software-YUV
  integration behavior.

## Acceptance Criteria

- Every Core Video texture reference used by rendering is owned by an
  `IRMetalFrameTextureGeneration`.
- Every submitted frame generation is retained through a command-buffer
  completion handler.
- Multi-view and distortion rendering reuse one generation per frame and
  command.
- Focused tests, Thread Sanitizer, rendering integration tests, the full
  simulator suite, and a generic iOS device build pass.
