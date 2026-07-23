# Player Facade Runtime Owners Design

## Summary

`IRPlayerImp` still owns presentation construction, render-mode selection,
gesture and motion control, media-source binding, backend construction and
commands, app lifecycle observation, audio interruption routing, idle-timer
side effects, typed events, legacy notifications, and teardown.

This change turns it into a migration/public API facade over explicit runtime
owners:

- `IRPlayerPresentationSession` owns the display view and all interaction
  resources;
- `IRPlayerEnvironmentSession` owns app/audio lifecycle observation and idle
  timer policy;
- `IRPlayerMediaSession` owns the current source and custom-input binding;
- `IRPlayerSettingsStore` owns synchronized facade configuration and errors;
- `IRPlaybackBackendCoordinator` serializes backend ownership and commands;
- `IRPlaybackBackendEventRouter` admits events only from the active backend.

The facade retains the 2.x public and Objective-C entry points, but no longer
stores raw rendering, motion, notification-token, or backend-lifecycle state.

## Problems

- `IRPlayerImp.renderMode` is never assigned, so the public selected-mode value
  remains `nil` even after successful selection.
- `viewTapAction` is never connected to the gesture controller.
- Replacing a custom `IRFFVideoInput` overwrites the facade reference without
  first stopping its backend and unbinding the old output.
- Display, gesture, smooth-scroll, sensor, notification, audio manager, source,
  settings, backend, and event responsibilities share one 588-line class.
- Selector-based app observers are registered globally and removed by broad
  object removal rather than exact owned tokens.
- `IRPlayerLifecycleController` mutable resume/grace-period state is accessed
  without synchronization by app and audio callbacks.
- `UIApplication.isIdleTimerDisabled` is changed directly by command methods
  and teardown, with no injectable or testable owner.
- `IRPlaybackBackendCoordinator` has no synchronization. Concurrent load,
  stop, play, pause, seek, or configuration refresh can race its backend
  dictionary and active identity.
- A stopped or inactive backend still holds the facade host and can publish
  stale state/progress/error events after replacement.
- Invalid loads publish an error but leave an `.empty` media source installed;
  backend factory failure has no player-level error.
- Backend replacement and source mutation are not one transaction. A new
  backend can observe partially changed URL/header/input state.
- `snapshot()` is a permanent `nil` stub despite the display view already
  providing framebuffer capture.
- The lifecycle policy retains unused backend-routing decisions that duplicate
  the backend coordinator and are tested only against themselves.
- Public settings and backend host reads can occur on different threads without
  a state owner.

## Goals

- Reduce `IRPlayerImp` to public API translation and owner composition.
- Make display, gestures, smooth scrolling, motion sensor, selected render
  mode, tap delivery, snapshot, and display teardown one presentation owner.
- Make app observers, audio event binding, lifecycle state, command dispatch,
  idle timer, and exact teardown one environment owner.
- Make media source/header/custom-input state synchronized and replace it only
  after the previous active backend has stopped.
- Serialize every backend ownership mutation and command.
- Reject events from inactive backend kinds.
- Publish an explicit final `.none` state when stopping active playback while
  suppressing backend cleanup noise.
- Keep backend-visible source/settings/display/audio values safe to snapshot
  from worker callbacks.
- Make backend and environment dependencies injectable for deterministic facade
  tests.
- Fix selected render mode, single-tap forwarding, stale custom-input output,
  invalid-load cleanup, backend-unavailable errors, and snapshot behavior.
- Remove unused facade backend-routing policy and consolidate environment
  decisions into their state owner.

## Non-Goals

- Split `IRGLView` surface/frame-submission internals in this slice; that is the
  next completion-audit boundary.
- Rewrite AVFoundation or FFmpeg backend internals.
- Remove the `IRPlayerImp` compatibility name or legacy selector notification
  API during the 2.x migration.
- Change Metal shaders, projection math, or render-mode visual semantics.
- Make mutable user-supplied `IRPlayerDecoder`, `IRFFVideoInput`, or
  `IRGLRenderMode` instances independently thread-safe.

## Facade Composition

```text
IRPlayer / IRPlayerImp
  |
  +-- IRPlayerSettingsStore
  +-- IRPlayerMediaSession
  +-- IRPlayerPresentationSession
  +-- IRPlayerEnvironmentSession
  +-- IRPlaybackBackendCoordinator
          |
          +-- AV host adapter --+
          +-- FF host adapter --+--> IRPlaybackBackendEventRouter
                                         |
                                         +--> typed + legacy event bridge
```

Dependencies point toward small protocols or value snapshots. Backends receive
kind-specific host adapters rather than the facade itself. The adapters expose
the synchronized context required by a backend and tag every callback with its
backend kind.

## Backend Replacement Transaction

Replacement is serialized by a coordinator mutation lock:

1. mark the coordinator inactive and deactivate event admission;
2. synchronously stop the previously active backend;
3. replace source/header/input state and unbind the old custom input;
4. apply the new video presentation;
5. lazily construct or retrieve the requested backend;
6. publish the new active identity and enable only its event adapter;
7. ask the backend to replace its resources;
8. bind the custom input to the resulting display/decoder output;
9. autoplay only after a backend was successfully selected.

Reset deactivates event admission before stopping cached backends, clears the
cache, then clears the media/input session. Backend-generated cleanup events
are rejected. The facade publishes one deterministic transition to `.none`
when the prior public snapshot was active.

## Presentation Ownership

`IRPlayerPresentationSession` implements `IRGLViewHost` and `IRGLViewDelegate`.
It creates and owns the `IRGLView`, gesture controller, smooth-scroll
controller, and optional motion sensor. It is the source of truth for gravity,
render modes, and current mode.

All UIKit mutation is marshalled to the main thread without holding owner
locks. Selecting an unregistered mode leaves the current mode unchanged.
Successful selection updates gesture and smooth-scroll mode references.
Single tap invokes the facade callback exactly once. Switching between gesture
and motion interaction drains the previous sensor/gesture resource before
installing the next. Close is terminal and idempotent.

Framebuffer snapshot uses the display view's existing capture implementation
instead of returning a permanent `nil`.

## Environment Ownership

`IRPlayerEnvironmentSession` owns exact block observer tokens for background
and foreground notifications. It installs one weak audio-manager event binding,
serializes all `IRPlayerLifecycleController` mutations, and invokes commands
outside its lock through an injected main-command dispatcher.

Replacing the audio manager removes the old binding before installing the new
one. Close removes exact observer tokens, removes the audio binding, clears
resume/grace-period state, and restores the idle timer. The system idle-timer
adapter performs UIKit mutation on the main thread; tests inject a recorder.

Lifecycle decisions live in `IRPlayerLifecycleController`, eliminating the
standalone `IRPlayerLifecyclePolicy`.

## Concurrency

- Backend ownership and commands use a mutation lock; state snapshots use a
  separate lock and never call a backend while that state lock is held.
- Public load and playback-control transactions enter through the main runtime
  thread before acquiring coordinator ownership, avoiding UIKit lock inversion.
- Settings, error, source, event admission, presentation identity, and
  environment binding have independent locks.
- UIKit work is executed on the main thread after state is snapshotted.
- The coordinator transaction lock deliberately spans backend commands so
  replacement and control remain serialized; narrower state/event owner locks
  are not held while invoking application callbacks, handlers, or tap closures.
- Event delivery remains main-queue serialized.
- Teardown deactivates environment and backend event sources before releasing
  media and presentation resources.

## Error Semantics

- Missing URL: reset backend/media state and emit `IRPlayer.Load` code `1`.
- Backend construction/kind mismatch: remain inactive, unbind custom output,
  and emit `IRPlayer.Load` code `2`.
- Invalid render-mode selection: preserve the previous mode without crashing.
- A stopped player exposes the empty backend snapshot and clears source,
  headers, input, error, lifecycle resume intent, and idle-timer state.

## Acceptance Criteria

- `IRPlayerImp` no longer owns raw display, gesture, sensor, scroll,
  notification-token, lifecycle-controller, media-input, or backend-dictionary
  state.
- Current render mode reflects configuration and successful selection.
- Single tap reaches `viewTapAction`; closing removes the gesture path.
- Old custom video input is unbound only after its active backend stops.
- App/audio observers and manager replacement have exact, idempotent cleanup.
- Concurrent coordinator commands/replacements are race-free and elect one
  ordered owner.
- Events from inactive backend kinds are rejected.
- Invalid source and backend-factory failure leave a clean inactive facade and
  emit one typed/legacy error.
- Presentation, environment, media, settings, coordinator, event-router, and
  facade integration behavior have focused tests.
- Affected suites pass under Thread Sanitizer.
- Full iOS Simulator tests, generic iOS build, project validation, and
  `git diff --check` pass.
