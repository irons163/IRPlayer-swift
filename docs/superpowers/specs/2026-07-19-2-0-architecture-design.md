# IRPlayer 2.0 Architecture Design

## Summary

IRPlayer 2.0 replaces concrete-object routing and notification-only observation with a layered playback architecture. The public player becomes a small facade over a backend coordinator, typed media source/configuration values, and typed events. AVFoundation and FFmpeg remain implementation details behind one backend protocol. Rendering remains independent from backend selection and consumes frames through its existing output contracts.

This is a major-version design. Internal compatibility is not a constraint. Existing public entry points remain as a migration layer where retaining them is inexpensive, but new code should use the typed 2.0 API.

## Problems In The Current Design

- `IRPlayerImp` owns public API, backend construction, backend switching, app lifecycle, audio interruption handling, rendering setup, gestures, sensors, notifications, and logging.
- `IRPlayerImp` repeatedly switches on `IRDecoderType` for commands and metrics.
- `IRAVPlayer` and `IRFFPlayer` depend directly on `IRPlayerImp`, which prevents isolated construction and replacement.
- The library exposes mutable setup in an order-dependent form (`decoder`, headers, video type, URL, then play).
- State, progress, playable duration, and errors are observable primarily through stringly typed `NotificationCenter` payloads.
- Pure decisions are spread across dozens of `*Policy.swift` files. Pure logic is valuable, but policy-per-function obscures ownership and produces a second, fragmented architecture beside the runtime types.
- `IRFFDecoder`, `IRGLView`, and `IRAVPlayer` are large objects with mixed state, scheduling, and resource responsibilities.

## Goals

- Provide one typed, discoverable API for loading media and observing playback.
- Route all backend commands and metrics through one coordinator.
- Make AVFoundation and FFmpeg conform to the same internal backend contract.
- Make backend switching deterministic and testable with fakes.
- Keep rendering selection independent from backend selection.
- Treat state transitions as explicit domain behavior, not incidental property observers.
- Keep blocking decode and render work off the main thread while delivering UI-facing events on the main queue.
- Preserve the legacy `IRPlayerImp` surface as a migration facade where practical.
- Add focused tests for every new boundary and keep the full iOS Simulator suite green.

## Non-Goals

- Reimplement FFmpeg codecs or replace the bundled FFmpeg binaries.
- Replace Metal shaders solely for stylistic consistency.
- Remove Objective-C compatibility in the same slice as the core routing change.
- Introduce a second playback implementation beside AVFoundation and FFmpeg.

## Target Layers

```text
Public API
  IRPlayer / IRPlayerImp migration facade
  IRMediaSource, IRPlayerConfiguration, IRPlayerEvent
          |
Playback Core
  IRPlaybackBackendCoordinator
  IRPlaybackBackend protocol
  state and lifecycle reducers
          |
Backend Adapters
  IRAVPlayer                  IRFFPlayer
  AVFoundation               IRFFDecoder + FFmpeg
          |                         |
          +-----------+-------------+
                      |
Rendering / Audio Ports
  IRFFDecoderVideoOutput, IRGLView, IRAudioManager
```

Dependencies point down. Backend implementations must not decide which backend is active. Rendering must not inspect the active backend. The facade must not duplicate backend switching.

## Public 2.0 API

### Media Source

`IRMediaSource` is the complete description of one load request:

- `url: URL?`
- HTTP headers
- video presentation type
- optional custom FFmpeg video input
- optional explicit backend preference

Loading one value replaces the order-dependent mutation of several player properties.

### Configuration

`IRPlayerConfiguration` contains player-wide behavior:

- decoder selection defaults
- autoplay
- live-stream behavior
- playable buffer interval
- volume
- gravity and display mode
- background policy

Configuration is validated and normalized before it is applied.

### Events

`IRPlayerEvent` provides typed state, progress, playable, and failure cases. The player offers token-based observation. Legacy notifications remain bridged from the same event source during migration.

### Naming

`IRPlayer` is the preferred Swift name. `IRPlayerImp` remains available for source compatibility during the 2.x line, but documentation and examples use `IRPlayer`.

## Playback Backend Contract

`IRPlaybackBackend` contains only the operations and read-only metrics required by the facade:

- identity (`avFoundation` or `ffmpeg`)
- state, progress, duration, playable duration, bitrate, presentation size, seeking
- play, pause, seek, stop, replace
- volume and buffer configuration refresh
- optional decoder video-input target

`IRPlaybackBackendCoordinator` owns backend instances, lazy construction, active backend identity, replacement, stop/reset, command routing, and metric defaults. It is tested entirely with fakes.

## State And Event Flow

Backends report changes to one event sink. The core updates its snapshot first, then publishes a typed event on the main queue. The legacy notification bridge consumes the same event. A state transition therefore has one ordering and one payload definition.

During incremental migration, current backend property observers may call the bridge, but the bridge must emit the typed event before posting the legacy notification.

## Concurrency

- Public UI operations are main-thread-facing.
- Backend coordinator ownership changes occur on the caller/UI thread.
- FFmpeg packet reading, decoding, and display scheduling remain on dedicated queues.
- Shared decode-loop state is mutated through its state owner and existing synchronization, not by unrelated callbacks.
- Event delivery is serialized on the main queue.
- Audio render callbacks remain allocation-free and do not dispatch synchronously to the main queue.

## Rendering

The render pipeline keeps `IRGLViewRenderState` and `IRGLViewRenderCoordinator` as its state and execution boundaries. The remaining `IRGLView` responsibilities are grouped into:

- surface/layout ownership
- mode configuration
- gesture forwarding
- frame submission
- snapshot delivery

Backend choice only selects the frame adapter/pixel format. Mode construction is driven by a render configuration value rather than switches distributed across player and view types.

## Policy Consolidation

New one-function policy files are prohibited. Existing policies are handled by domain:

- state transitions move into state-machine/reducer types;
- value normalization moves beside the value type;
- resource decisions move beside the resource owner;
- genuinely shared algorithms remain named helpers.

Consolidation is behavior-preserving and is performed only with existing or new focused coverage.

## Error Handling

- Loading an invalid source produces a typed failure and a legacy error notification.
- Backend creation and replacement failures leave the coordinator without an active backend.
- Public APIs do not crash for missing media, display resources, or unsupported formats.
- Errors keep their underlying `NSError` for Objective-C and FFmpeg interoperability.

## Testing Strategy

- Coordinator tests use fake backends and verify creation, replacement, routing, reset, and metrics.
- Media source/configuration tests verify defaults and normalization.
- Event tests verify typed delivery, cancellation, main-queue delivery, and legacy notification bridging.
- Existing backend tests remain focused on AVFoundation and FFmpeg behavior.
- Render tests cover 2D, VR, fisheye, fish2pano, distortion, and multi4P paths.
- Full acceptance uses the iOS Simulator Xcode scheme; `swift test` is not the iOS acceptance gate.

## Acceptance Criteria

- A caller can configure, load, observe, play, pause, seek, stop, and replace media without directly selecting a concrete backend object.
- `IRPlayerImp` no longer contains repeated backend routing switches.
- AVFoundation and FFmpeg conform to one playback backend protocol.
- Backend coordinator behavior is covered with deterministic fake-based tests.
- Typed events and the legacy notification bridge have focused tests.
- The render refactor final verification is complete.
- `git diff --check`, focused suites, and the full iOS Simulator test suite pass.
- Public 2.0 usage and migration notes are documented.
