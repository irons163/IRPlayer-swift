# FF Player Runtime Owners Design

## Summary

`IRFFPlayer` is the remaining backend adapter that owns mutable playback state,
decoder lifetime, command sequencing, decoder delegate callbacks, audio output
state, host event delivery, display configuration, and teardown in one object.
Those responsibilities currently run on caller, FFmpeg worker, audio, and main
threads without one execution domain or decoder-generation identity.

This change keeps `IRFFPlayer` as the `IRPlaybackBackend` adapter while moving
runtime behavior into explicit owners:

- `IRFFPlayerExecutor` owns one reentrant-safe serial execution domain;
- `IRFFPlayerStateMachine` owns play intent, preparation state, and playback
  transitions;
- `IRFFPlayerDecoderSession` owns one decoder generation, its delegate bridge,
  seek requests, and deterministic reset/close;
- `IRFFPlayerRuntime` owns serialized playback/time state, audio sequencing,
  decoder commands, current-generation event handling, and host events;
- `IRFFPlayerPresentation` translates FFmpeg configuration into main-thread
  display settings.

The existing one-function `IRFFPlayerPlaybackPolicy` is removed. Its decisions
become state-machine behavior.

## Problems

- `decoder`, `playing`, `prepareToken`, `progress`, `playableTime`, and progress
  throttling values are independently mutable.
- Public commands and decoder delegate callbacks may mutate those values from
  different threads.
- `IRPlayerStateStore` serializes only the enum value; it does not serialize the
  associated audio and host-event side effects.
- Decoder close is asynchronous. The player clears its decoder reference
  without detaching the old delegate, so an old decoder can still update a
  stopped or replacement player.
- Delegate callbacks accept any decoder identity, including decoders never
  installed by the player.
- Seek completions have no generation fence and are not completed when no
  decoder exists.
- `seeking` is stored separately and never follows the decoder, so FFmpeg
  backend snapshots can report a permanently false value.
- Backend snapshot fields are read independently and can span different decoder
  generations.
- Replacement interleaves decoder cleanup, display mutation, decoder
  construction, decoder opening, audio configuration, and buffer configuration
  without an explicit transaction boundary.
- Deinitialization runs normal cleanup and can publish user-visible state/time
  events while the backend is being destroyed.
- `IRFFPlayerPlaybackPolicy` duplicates state rules outside the owner that
  stores play intent and preparation state.

## Goals

- Serialize every mutable FF player runtime value and side effect.
- Make executor reentrancy safe for synchronous decoder callbacks and host
  reentry.
- Give every decoder generation a token and dedicated delegate bridge.
- Reject callbacks from replaced, reset, unknown, or closed decoders.
- Detach a decoder delegate before asynchronous decoder close begins.
- Stop Core Audio and drain the audio renderer before detaching or closing its
  decoder source.
- Own seek requests per decoder generation, complete displaced/stale requests
  exactly once, and return `false` when no decoder is active.
- Publish coherent backend snapshots from one execution transaction.
- Make reset repeatable and close terminal/idempotent.
- Keep deinitialization silent.
- Perform all display mutation on main and configure presentation before a new
  decoder can emit frames.
- Preserve normal, VR, fisheye, panorama, and custom FFmpeg presentation
  behavior.
- Consolidate playback decisions into the state machine.
- Add deterministic lifecycle, ordering, stale-work, failure, reentrancy, and
  concurrency tests.

## Non-Goals

- Reimplement the FFmpeg decode pipeline or its resource session.
- Change codec selection, projection math, or audio sample format.
- Make caller-owned custom video inputs independently thread-safe.
- Change the public `IRPlaybackBackend` command surface.
- Edit bundled FFmpeg frameworks.

## Execution Domain

`IRFFPlayerExecutor` wraps a serial queue with a dispatch-specific identity.
Synchronous work executes inline when already in the domain and otherwise uses
`queue.sync`. Decoder events, state/time updates, commands, metrics, reset, and
close all use this domain.

No executor transaction synchronously requests UIKit state from main.
Replacement captures its host/display request and applies presentation on main
before activating the decoder runtime. This prevents render-to-main and
main-to-runtime lock inversion.

## State Machine

`IRFFPlayerStateMachine` owns:

- current `IRPlayerState`;
- whether playback is requested;
- whether a non-buffering prepared state has already been emitted.

It returns explicit state transitions and command decisions for play, pause,
buffering changes, direct state changes, reset, and silent close. The runtime
applies each accepted transition once:

1. update host error state;
2. start or stop the audio manager and renderer;
3. publish the backend state event.

Repeated states have no side effects.

## Decoder Session

`IRFFPlayerDecoderSession` has phases:

- `idle`: no decoder is owned;
- `active`: one complete decoder generation is owned;
- `closed`: terminal.

Activation constructs and configures the decoder locally, creates a token and a
generation-specific delegate bridge, publishes the complete generation, runs
the runtime activation hook, and only then opens the decoder.

The bridge converts `IRFFDecoderDelegate` callbacks into typed decoder events.
The session admits an event only when token and decoder identity still match
the active generation. Reset removes the generation first, cancels its seek
tickets, detaches delegate/output/source links, and then closes the decoder.
Close enters the terminal phase before invoking cancellation completions or
decoder cleanup. Replacement rechecks the phase and owned generation after
draining so a reentrant completion cannot resurrect a closed session or have a
newer generation silently overwritten.

Activation also fences the injected factory boundary. If factory execution
reentrantly closes the session or installs a newer decoder, the outer
activation cannot overwrite it; any unpublished decoder is detached and
closed deterministically.

Seek tickets are lock-protected exactly-once completions. Reset/replacement
finishes pending tickets with `false`; a late decoder completion cannot finish
the same ticket again or control a replacement generation.

## Runtime

`IRFFPlayerRuntime` composes the executor, state machine, decoder session,
dedicated `IRFFAudioRenderer`, audio manager, weak backend host, and time state.

It owns:

- play/pause/seek commands;
- state and play intent;
- progress/playable values and progress-notification throttling;
- decoder metrics and coherent snapshots;
- volume/live-buffer configuration;
- decoder event reduction;
- audio start/pause/reset ordering;
- repeatable reset and terminal close.

Reset order is:

1. pause the audio manager;
2. disable and drain the audio renderer;
3. reset the decoder session, detach the delegate, and initiate decoder close;
4. reset state/time values and publish normal stop events.

Close follows the same resource order but clears state silently and unregisters
the audio session exactly once.

Runtime lifecycle generations fence multi-event failure delivery. If a
synchronous state observer replaces or resets the decoder while handling a
failure transition, the obsolete failure payload is not delivered into the new
runtime generation.

Playback-command generations fence `play()` and `pause()` around synchronous
decoder work. Play intent is visible before `resume()` callbacks, and a
reentrant later play/pause command wins instead of being overwritten when the
outer decoder call returns. Finished playback reuses a restart seek already
started by the decoder and requests one only when needed.

## Presentation

`IRFFPlayerPresentation` is a small value/applicator. It maps hardware decode to
NV12 and software decode to YUV. It maps VR to
`FFmpegPixelBufferVR` and every other FFmpeg video type to
`FFmpegPixelBuffer`.

The adapter runs presentation and empty-buffer cleanup through
`IRMainThreadExecutor`. Missing URL/host remains a reset no-op; a missing
display remains a deterministic backend failure.

Facade presentation commands have a main-thread generation so a reentrant
replace or stop request supersedes an older request. Deinitialization closes
runtime resources silently but does not enqueue a stale clear against a display
that may already belong to another backend; explicit stop/replacement owns
display cleanup.

## Compatibility

- `IRFFPlayer` remains an `NSObject` and `IRPlaybackBackend`.
- Existing internal test helpers for state, decoder, audio manager, play intent,
  progress, playable time, and current audio frame become computed views over
  the runtime.
- Static transition wrappers remain available but delegate to
  `IRFFPlayerStateMachine`, not a policy namespace.
- Decoder delegate conformance moves from the adapter to generation bridges.
- Audio sample copying remains in `IRFFAudioRenderer`.

## Error And Teardown Semantics

- Events from unknown or stale decoders are counted and ignored.
- Reentrant cancellation callbacks cannot overwrite a newer generation or
  install a decoder after terminal close.
- Reentrant factory, playback-command, failure, and presentation work is
  generation-fenced so the newest request wins.
- Replacement/reset cancel pending seeks with `false`.
- Seeking without an active decoder completes with `false`.
- Repeated reset is a no-op after the first complete cleanup.
- Close rejects activation, adoption, commands, and new seeks.
- Decoder delegate, source, video output, and audio output are detached before
  close.
- A failed replacement leaves no active decoder.
- Deinitialization publishes no state, progress, playable, or failure event.

## Acceptance Criteria

- `IRFFPlayer` no longer stores mutable decoder, playback, time, seek, or audio
  runtime state.
- All commands and decoder events share one reentrant-safe execution domain.
- Old/unknown decoder callbacks cannot mutate the active generation.
- Reentrant replacement and failure notification cannot cross generations.
- Synchronous decoder callbacks cannot overwrite a newer play/pause or
  presentation command.
- Audio stops and drains before decoder close.
- Seek completion is exactly once and generation-fenced.
- FFmpeg backend snapshot values are coherent and seeking reflects the active
  decoder.
- Reset is repeatable; close is terminal/idempotent; deinit is silent.
- Presentation mutation stays on main and precedes decoder opening.
- Playback policy decisions live in `IRFFPlayerStateMachine`.
- Owner tests cover activation, adoption, replacement, stale callbacks, seek
  cancellation, failure, ordering, reentrancy, concurrent commands/events,
  reset, close, and presentation mapping.
- Focused suites pass with Thread Sanitizer.
- Full iOS Simulator tests, generic iOS build, project validation, and
  `git diff --check` pass.
