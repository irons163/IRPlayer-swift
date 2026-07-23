# Audio Output Session Lifecycle Design

## Summary

`IRAudioManager` currently mixes notification parsing, handler registration,
AUGraph construction, graph control, render callback state, sample conversion,
and scratch-buffer ownership in one object. The main/control thread mutates the
same properties that the real-time callback reads, while failed graph setup can
publish and leak a partially constructed graph.

This change introduces three explicit runtime owners:

- `IRAudioGraphSession` serializes graph lifecycle and owns exactly one complete
  graph generation;
- `IRAudioRenderContext` owns callback state and the preallocated scratch buffer
  behind a non-blocking real-time admission gate;
- `IRFFAudioRenderer` owns FFPlayer audio-frame consumption independently of the
  player facade.

The platform Core Audio calls are isolated behind `IRAudioGraphDriving`.
`IRCoreAudioGraphDriver` builds and tears down the real AUGraph, while its
low-level call boundary is injectable so every partial-construction failure can
be verified without relying on device hardware.

## Problems

- `registered`, `outputContext`, `_playing`, `delegate`, and `_outData` are read
  and written concurrently by control code and the audio callback.
- The callback refcon is an unretained `IRAudioManager`; graph teardown and
  manager destruction have no in-flight callback fence.
- `setupAudioUnit` publishes its local context with `defer`, including on
  failure. Because failed setup never marks the manager registered,
  `unregisterAudioSession` will not dispose that partial graph.
- Register, start, stop, unregister, volume access, and deinit are not
  serialized and can target a graph or audio unit while another call disposes
  it.
- The test-only registration closure can report a registered session without a
  graph, producing an impossible state that cannot be unregistered.
- Graph failure paths are largely untestable because all Core Audio calls are
  embedded directly in the manager.
- The render callback validates only scratch-buffer capacity. It does not
  validate destination `mDataByteSize`, so malformed buffers can be
  overwritten.
- Non-interleaved buffers restart source-channel indexing at zero for every
  buffer and therefore duplicate channel zero.
- Integer output is scaled without clamping, allowing out-of-range samples to
  overflow during conversion.
- Notification handlers and their weak target are installed and removed without
  synchronization.
- `IRFFPlayer` mutates `currentAudioFrame`, `playing`, and `decoder` from control
  code while the audio callback reads and changes them. Decoder close currently
  starts before audio output is synchronously stopped.
- The standalone `IRAudioManagerPolicy` separates small invariants from the
  owners that enforce them.

## Goals

- Model graph phases explicitly: idle, building, ready, running, resetting, and
  closed.
- Serialize prepare/start/pause/reset/close and all graph/audio-unit commands.
- Publish only a fully opened and initialized graph.
- Dispose a partially built graph exactly once at every mandatory failure stage.
- Make prepare retryable, reset repeatable, and close terminal/idempotent.
- Deactivate and drain the render callback before stopping or disposing graph
  resources.
- Keep manager-owned callback mechanics allocation-free and use non-blocking
  admission on the real-time path.
- Use a non-waiting decoder dequeue so an empty/just-flushed frame queue returns
  silence instead of polling on the real-time callback.
- Pre-silence every destination and the scratch buffer so rejected or partial
  rendering is deterministic.
- Validate requested frames, channels, scratch capacity, destination byte
  capacity, and supported PCM format before copying.
- Map interleaved and non-interleaved channels correctly and clamp Int16 output.
- Synchronize notification binding without retaining the handler target.
- Move FFmpeg frame consumption into a dedicated renderer whose callback uses a
  non-blocking lock and whose reset is fenced from rendering.
- Stop and drain audio output before closing an FFmpeg decoder.
- Remove `IRAudioManagerPolicy` and impossible test-only registration state.

## Non-Goals

- Override an application's `AVAudioSession` category, mode, or activation
  policy.
- Replace AUGraph with AVAudioEngine in this slice.
- Allocate, log, post notifications, or invoke player-host callbacks from the
  real-time render path.
- Make arbitrary delegate implementations thread-safe; the manager guarantees
  safe binding and teardown, while the FFmpeg implementation supplies its own
  synchronized renderer.
- Support PCM layouts beyond the graph's validated Float32 or signed Int16
  output.

## Graph Lifecycle

```text
idle --prepare--> building --publish--> ready --start--> running
  ^                   |                    ^             |
  |                   +--failure----------+             +--pause--+
  |                                                               |
  +-------------------------- reset <------------------------------+

idle/building/ready/running/resetting --close--> closed
```

All mutations are elected by one mutation lock. Read-only diagnostics and
format snapshots use a separate state lock. Driver calls occur without the
state lock held.

Prepare builds into local resources. A complete graph is published only after
node creation, connections, audio-unit lookup, callback installation, format
validation/configuration, and initialization all succeed. Failure cleanup uses
the exact construction flags:

1. uninitialize only if initialization succeeded;
2. close only if graph open succeeded;
3. dispose every created graph exactly once.

Reset drains a ready/running graph back to idle so a later FFmpeg backend can
prepare a new generation. Close performs the same drain but transitions
terminally to closed.

## Render Callback Ownership

The graph callback refcon points to `IRAudioRenderContext`, not the manager. The
graph session retains that context for its entire lifetime. Before graph stop or
teardown, the context is deactivated and control waits for an admitted render
call to finish.

The callback first clears all destination buffers. It then attempts, but never
waits for, the render gate. Contention, inactive state, missing owner/delegate,
invalid frame/channel counts, unsupported format, or insufficient destination
capacity all return silence.

Accepted PCM descriptions must be native-endian, packed, one-frame-per-packet
Float32 or signed Int16 with byte strides consistent with their interleaved or
non-interleaved channel layout.

An admitted callback:

1. clears the preallocated interleaved Float scratch buffer;
2. asks the current delegate to fill it;
3. validates every destination buffer;
4. copies Float32 samples or clamps/scales/converts signed Int16 samples;
5. advances a global source-channel offset across non-interleaved buffers.

No callback-visible resource is deallocated until graph stop and disposal have
completed.

## FFmpeg Audio Adapter

`IRFFAudioRenderer` owns the current decoded audio frame and frame source. The
audio thread uses `try()` on its render lock; contention produces already
prepared silence rather than priority inversion. Control operations may wait
for a render to finish, then safely clear/stop the current frame.

FFPlayer activates the renderer before starting audio output. Pause and cleanup
first synchronously pause the audio graph, then deactivate/reset the renderer,
and only then close the decoder. `IRFFPlayer` no longer serves directly as the
audio-manager delegate.

The decoder adapter performs one asynchronous queue dequeue per requested
frame. It never enters the queue's polling `getFrameSync()` path from the audio
callback; an empty or concurrently flushed queue simply yields silence.

## Event Ownership

The manager owns block-based interruption and route-change observer tokens and
removes those exact tokens on deinit. A synchronized event router owns one weak
target plus its handlers. Delivery snapshots a valid binding under lock and
invokes it outside the lock so handlers may re-enter player lifecycle code.

Payload parsing moves into `IRAudioManager` because it is part of the manager's
notification boundary rather than a separate policy abstraction.

## Acceptance Criteria

- `IRAudioManager` no longer owns raw graph, audio-unit, scratch-buffer, playing,
  or registered fields.
- The real-time callback never dereferences an unretained manager refcon.
- Concurrent prepare/start/pause/reset/close cannot duplicate setup or target a
  disposed graph.
- Every injected graph-build failure drains partial resources exactly once and
  remains retryable.
- Render/reset and render/close races are fenced; rejected callbacks return
  silence.
- Interleaved Float32, non-interleaved Float32, Int16 clipping, malformed
  buffers, oversized requests, and inactive rendering have regression tests.
- Unpacked or byte-stride-inconsistent PCM descriptions are rejected and
  cleaned without publication.
- Notification target replacement/removal and manager deinit are safe.
- FFPlayer audio output is stopped before decoder close and current-frame reset.
- The superseded policy file and direct FFPlayer audio delegate implementation
  are removed.
- Focused lifecycle/failure/render/integration suites pass under Thread
  Sanitizer.
- Full iOS Simulator tests and a generic iOS device build pass.
