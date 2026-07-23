# GL View Runtime Owners Design

## Summary

`IRGLView` is the remaining display-runtime monolith. It currently owns UIKit
layout, the `CAMetalLayer`, Metal device/queue/context construction, drawable
size, selected render modes, submitted frame/image state, render dispatch,
mode-specific GPU state, AVPlayer-layer attachment, snapshot requests, album
saving, and teardown.

This change keeps `IRGLView` as the public UIKit boundary while moving runtime
state into explicit owners:

- `IRGLRenderExecutor` owns the reentrant-safe serial render domain;
- `IRGLMetalSurfaceSession` owns one complete Metal resource generation;
- `IRGLFrameSubmissionSession` owns accepted frame/image state and render
  completion accounting;
- `IRGLRenderSession` owns render modes, viewport, interaction mutations,
  surface/frame composition, and terminal teardown;
- `IRGLSnapshotSession` owns coalesced snapshot requests and cancellable
  main-thread delivery;
- `IRGLAVPlayerLayerSession` owns AVPlayer-layer attachment, gravity, layout,
  and deterministic detachment.

The view becomes a translation layer between UIKit inputs and those owners.

## Problems

- `IRGLView` has mutable Metal, frame, mode, snapshot, and layout state spread
  across more than 800 lines.
- `send(videoFrame:)` can arrive on decoder threads while layout, mode
  selection, cleanup, and snapshot calls arrive on main or application
  threads.
- `queue.sync` is used directly and has no queue-identity check, so reentrant
  calls can deadlock.
- `choose(renderMode:)` mutates `aspect` from the render queue; its observer
  performs UIKit layout from that queue.
- `rendererType`, `mode`, `modes`, viewport, frame dimensions, and the snapshot
  flag are unsynchronized.
- Metal reset can race frame submission or view teardown, and resource
  construction failures have no explicit phase or diagnostics.
- Fish2pano lookup maps are built on a background queue while render submission
  polls and releases their raw buffers without a shared publication boundary.
- `close()` is not represented as a terminal state; later submissions and
  reconfiguration have no defined rejection behavior.
- Snapshot completion schedules a main-queue block after every completed
  render and checks a racy boolean only after scheduling.
- A queued snapshot can still run after teardown.
- AVPlayer-layer lifetime and Metal lifetime are interleaved in the view.
- `cleanEmptyBuffer()` is a stub, so stop/reset does not deterministically
  clear the last displayed Metal content.
- `IRGLViewPolicy` and `IRGLRenderStrategyPolicy` are one-function namespaces
  detached from the owners whose invariants they describe.

## Goals

- Make every mutable render-path value owned by one serialized runtime.
- Make render-queue reentrancy safe without blocking the main thread in the
  per-frame path.
- Capture UIKit geometry on main before entering the render domain.
- Publish only complete Metal resource generations.
- Make unavailable-device and invalid-size states explicit and retryable.
- Make close terminal, idempotent, and reject later mutation/submission.
- Preserve frame redraw semantics and every render mode: 2D, flat multi,
  VR, fisheye, fish2pano, distortion, and multi4P.
- Make current frame dimensions, mode, viewport, lifecycle, and counters
  available as coherent diagnostics.
- Coalesce pending album-snapshot requests, schedule only after a completed
  render, and cancel stale scheduled work after close.
- Keep direct framebuffer capture synchronous and main-thread safe.
- Detach AVPlayer layers exactly once and keep all layer mutation on main.
- Implement empty-buffer cleanup as an actual black-frame render.
- Consolidate view/strategy policies into their domain owners.
- Publish fish2pano lookup buffers as immutable generations and retain consumed
  generations until the renderer explicitly releases them.
- Add deterministic failure, lifecycle, ordering, reentrancy, and concurrency
  tests around each owner.

## Non-Goals

- Change shader code, mesh/projection math, or visual render semantics.
- Change public `IRGLView` construction or `IRFFDecoderVideoOutput` APIs.
- Make mutable caller-provided `IRGLRenderMode` objects independently safe when
  callers mutate them outside `IRGLView`.
- Rewrite AVFoundation or FFmpeg playback backends in this slice.
- Introduce asynchronous frame queuing or change the decoder's synchronous
  submission contract.

## Render Domain

`IRGLRenderExecutor` wraps one serial queue and installs a dispatch-specific
identity. `sync` executes inline when already in that domain and otherwise
uses `queue.sync`. This preserves synchronous frame submission and eliminates
self-deadlock from render callbacks or test hooks.

No render-domain operation synchronously asks main for UIKit state. The view
captures bounds, scale, superview geometry, gravity, and layer identity on main
before calling the runtime. Main may wait for a finite render transaction, but
the render transaction never waits for main.

## Metal Surface Ownership

`IRGLMetalSurfaceSession` has explicit phases:

- `idle`: no resource generation has been requested;
- `ready`: layer, device, command queue, CI context, and renderer are complete;
- `unavailable`: a generation could not be built and can be retried;
- `closed`: terminal; prepare and resize are rejected.

Prepare clears the previous generation, configures the supplied
`CAMetalLayer`, creates all resources locally, and publishes them only after
every mandatory resource exists. Resize validates finite positive pixel
geometry before changing `drawableSize` and the published backing dimensions.
Invalid geometry preserves the previous valid dimensions.

Close releases the complete generation once. Diagnostics expose generation,
prepare/resize/rejection counts, resource completeness, and pixel size.

## Frame Submission And Modes

`IRGLRenderSession` is the aggregate owner for one view. It confines these
values to the render executor:

- pixel format;
- registered/current render modes;
- viewport and content mode;
- surface session;
- frame-submission session;
- mode-specific `IRGLViewRenderState`.

`IRGLFrameSubmissionSession` owns current frame, fallback CI image, last frame
size, submission/redraw/completion/drop counters, and close state. A non-nil
frame atomically replaces the previous frame and clears its converted image.
A nil frame redraws current content. Unsupported frames remain diagnosable but
do not fabricate a successful render.

Mode selection validates membership, builds/reuses the program and renderer,
configures mode-specific state, and returns the selected aspect to the view.
UIKit layout happens only after that transaction returns.

Viewport, pinch, pan, degree-scroll, clear, mode selection, surface
reconfiguration, submission, and close all share the same serial domain.
`cleanEmptyBuffer()` installs a black CI image, removes the current frame, and
attempts one render through the normal frame session.

Fish2pano lookup generation captures an immutable configuration before entering
its worker queue. The completed buffer is published under one state lock only
if its generation is current. Consumption transfers that buffer into an
independently retained set until texture upload releases it, so a newer lookup
generation cannot overwrite or free memory still in use.

## Snapshot Ownership

`IRGLSnapshotSession` has a lock-protected request generation and lifecycle
epoch:

1. `request()` records one pending request; repeated requests before a render
   are coalesced and counted.
2. A completed render consumes at most one pending generation.
3. Only then is a main-thread capture scheduled.
4. The scheduled closure revalidates its epoch before capture and save.
5. `close()` cancels pending and already scheduled stale work.

The session accepts injected dispatcher, capture, and save dependencies for
tests. Production capture renders the view hierarchy on main and production
save uses `IRPhotoSaver`.

Direct `createImageFromFramebuffer()` does not depend on a pending album
request. It synchronously enters main and returns an empty image for invalid
geometry.

## AVPlayer Layer Ownership

`IRGLAVPlayerLayerSession` performs all work on main. It creates at most one
layer, reuses it across player replacement, keeps frame and gravity current,
and detaches player/layer during reset or close. Close is terminal and
idempotent. Diagnostics expose attachment, layer generation, layout, and
detach counts.

Renderer-type transitions are serialized by the view's presentation-state
lock and applied on main. Cleanup retains only the surface selected by the new
renderer type.

## Compatibility

- `IRGLView` remains a `UIView` and `IRFFDecoderVideoOutput`.
- Existing internal mode, viewport, aspect, renderer-type, queue-helper,
  snapshot, AVPlayer, and cleanup entry points remain callable.
- `mode`, `modes`, viewport, last-frame dimensions, and pending-snapshot state
  become computed views over their owners rather than independent storage.
- `IRGLViewPolicy` wrappers move to the surface/frame/render-state owners.
- Strategy classification moves into `IRGLRenderStrategyFactory`; strategy
  implementations move out of `IRGLView.swift`.

## Error And Teardown Semantics

- Missing Metal device or any mandatory surface resource produces
  `.unavailable`; no partial resource snapshot is published.
- Invalid drawable size does not erase the previous valid size.
- Closed surface/render/snapshot/AV-layer sessions reject later work.
- Close deactivates snapshot delivery, detaches AVPlayer, then closes the
  render domain.
- Repeated close performs no additional teardown.
- Frame submission after close returns without invoking a renderer.
- Stale fish2pano lookup jobs are discarded without replacing the published
  generation, and consumed lookup memory cannot be reclaimed by a newer job.

## Acceptance Criteria

- `IRGLView` no longer stores raw Metal resources, current frame/image,
  render-state caches, AVPlayer layer, or snapshot-request state.
- Render-domain reentrancy cannot self-deadlock.
- No UIKit layout/layer access occurs from the render queue.
- Surface generations are complete-or-unavailable and retryable before close.
- Mode selection and every renderer path preserve existing behavior.
- Empty-buffer cleanup renders black and clears the current frame.
- Snapshot requests coalesce, deliver only after render completion, and are
  cancelled by close.
- AVPlayer attachment/layout/gravity/teardown are deterministic.
- Concurrent submission, redraw, mode reads, snapshot requests, reset, and
  close are race-free.
- Owner tests cover success, invalid input, unavailable resources, retry,
  reentrancy, concurrent access, close, and stale-work cancellation.
- Focused suites pass with Thread Sanitizer.
- Full iOS Simulator tests, generic iOS build, project validation, and
  `git diff --check` pass.
