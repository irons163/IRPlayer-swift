# AVPlayer Session Lifecycle Design

## Summary

`IRAVPlayer` currently owns an asset, item, player, video output, three manual
KVO registrations, an end notification, a periodic time observer, and
asynchronous asset loading as unrelated mutable properties. Replacement relies
on a particular cleanup call order and asynchronous callbacks identify the
current media by reading those mutable properties.

This change introduces `IRAVPlayerSession` as the single repeatable owner of one
AVFoundation media generation. It atomically publishes a complete asset/item/
player graph, owns every observation token, rejects stale asynchronous work by
generation, leases resources during external use, and tears down in one
deterministic order.

## Problems

- A VR asset-load callback reads `self.avAsset`; after replacement it can inspect
  and mutate the new media session instead of the asset that initiated it.
- A seek completion and delayed play retry can arrive after replacement and
  affect the new player.
- Three string-key KVO registrations are represented by one Boolean, so repeated
  or partial setup can make removal target the wrong item.
- The end notification handler does not independently validate media identity.
- Output replacement can remove an output while display/snapshot work is using
  session resources.
- `deinit` calls the normal reset path, which emits host progress/state/display
  callbacks during destruction.
- A video output and active display-link polling are created for normal
  `AVPlayerLayer` playback even though only VR rendering consumes pixel buffers.
- Selecting the `AVPlayerLayer` renderer changes an enum but does not attach an
  actual `AVPlayerLayer`, so normal playback has no dedicated native presentation
  surface.
- `IRAVPlayer` mixes lifecycle, presentation, track selection, and playback
  commands in one large facade.
- Thin asset-load and redirect policy types separate decisions from the resource
  owner without adding an abstraction boundary.

## Goals

- Model a repeatable session as empty, building, active, reconfiguring, resetting,
  or closed.
- Assign every activation a monotonically increasing generation token.
- Publish the asset, item, and player only as one active resource graph.
- Own typed KVO tokens, the end-notification token, and the periodic-time token.
- Deliver observation callbacks on the main queue only after generation and
  item identity validation.
- Fence reset/output rebuild against active resource leases.
- Cancel loading, seeks, prerolls, observers, output, and player ownership in a
  deterministic order.
- Reject stale asset-load, seek-completion, and delayed-retry callbacks.
- Keep normal playback on `AVPlayerLayer` without a video output or active
  display-link polling.
- Bind and detach the current AV player through a real `AVPlayerLayer` owned by
  the display surface.
- Split backend lifecycle, presentation, and track behavior into focused files
  while retaining the public backend facade.
- Make deinitialization a silent resource close.

## Non-Goals

- Replace AVFoundation playback or change public playback APIs.
- Add custom/fisheye/panorama support to the AVFoundation backend.
- Change buffering thresholds, media-selection behavior, or error payload
  contents.
- Hold the session condition while invoking AVFoundation methods or backend-host
  callbacks.

## Lifecycle

```text
empty --activate--> building --publish--> active
  ^                                  |
  |                                  +--rebuild output--> reconfiguring
  |                                                        |
  +------------------------- reset <-----------------------+

empty/building/active/reconfiguring --close--> closed
```

Every activate/reset/close advances session identity. A token is current only
when its generation matches an active session and, when supplied, its asset or
item is the exact owned object.

## Resource And Observation Ownership

Activation creates the item and player, installs typed key-path observations,
registers the item-scoped end notification, and adds the periodic time observer.
Only after the entire graph is ready is it published as active.

External reads use `withResources`, which registers a short lease. Reset stops
new leases, waits for existing leases, drains the graph, then performs teardown
outside the condition:

1. invalidate KVO and end-notification tokens;
2. remove the periodic observer from its owning player;
3. cancel asset loading and clear its resource-loader delegate;
4. cancel item seeks;
5. pause/cancel the player and detach its item;
6. remove the owned video output.

VR output installation/replacement uses the same lease fence. Normal playback
does not install an output.

## Presentation Ownership

`IRGLView` owns the native `AVPlayerLayer` because it owns display-surface
lifetime and layout. Normal AVFoundation playback attaches the session player
to that layer. Reset, backend replacement, renderer changes, and close detach
it. VR playback explicitly keeps the native layer detached and presents leased
pixel buffers through the existing display link and Metal path.

The backend facade is split by responsibility:

- `IRAVPlayer.swift` owns playback commands and facade state;
- `IRAVPlayerLifecycle.swift` translates session events and replacement/reset;
- `IRAVPlayerPresentation.swift` owns time, snapshot, output, and display-link
  behavior;
- `IRAVPlayerTracks.swift` owns media selection and metadata access;
- `IRAVPlayerSession.swift` owns the AVFoundation resource graph.

## Callback Semantics

- Observation and periodic callbacks carry the activation generation.
- Stale callbacks are discarded before reaching `IRAVPlayer`.
- Asset-key completion reads the captured asset, then verifies the asset/token
  pair before reporting failure or installing output.
- Seek completion reports `false` when its item/token is no longer current and
  never mutates the replacement session.
- Delayed play retry captures a token and acts only on the same current player.
- End-of-item delivery is item-scoped and generation-checked.

## Policy Consolidation

Asset-load and HTTPS-header redirect decisions move next to the session/facade
that consumes them. `IRAVPlayerAssetLoadPolicy` and
`IRAVPlayerResourceLoaderPolicy` are removed. Existing playback, time, track,
and error domain helpers remain until their runtime boundary is changed.

## Acceptance Criteria

- `IRAVPlayer` no longer stores AV asset/item/player/output or observation-token
  properties independently.
- Manual string-key KVO and `observeValue` are removed.
- Replacement and close release every observer/resource exactly once.
- Stale generation callbacks cannot alter the current player.
- Reset/output rebuild wait for registered resource users.
- Normal playback has no pixel-buffer output; VR installs one after asset keys
  load successfully.
- Normal playback attaches the current player to a real `AVPlayerLayer`; VR and
  reset paths leave that layer detached.
- Lifecycle, presentation, track, and resource ownership are separated into
  focused implementation files.
- Deinit performs no backend-host notifications.
- New lifecycle, stale-callback, lease, reset, and close tests pass under Thread
  Sanitizer.
- Full iOS Simulator tests and a generic iOS device build pass.
