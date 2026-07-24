# AVPlayer Presentation Loop Ownership Design

## Context

Normal AVPlayer playback is presented by `AVPlayerLayer`, while VR playback
polls `AVPlayerItemVideoOutput` from a `CADisplayLink` and submits each pixel
buffer to the Metal display view.

The AVFoundation asset, item, player, output, observations, and time observer
already belong to `IRAVPlayerSession`. The polling resource does not:

- `IRAVPlayer` stores a raw `CADisplayLink` and its proxy;
- setup, pause, activation, reset, and invalidation are spread across the
  facade, lifecycle, and presentation extensions;
- tests reach into the concrete UIKit timer to invalidate it or inspect
  `isPaused`;
- installation failure and off-main construction are not observable;
- there is no terminal phase or atomic diagnostic snapshot;
- a tick captured before normal/VR replacement or reset has no presentation
  generation to reject it before rendering; and
- smooth scrolling already implements almost the same native display-link
  resource wrapper under a feature-specific name.

The 2.0 boundary should have one reusable native display-link driver and one
AVPlayer-specific presentation-loop owner that binds active ticks to the exact
AVFoundation resource generation.

## Goals

1. Promote the existing smooth-scroll system wrapper into a reusable
   `IRDisplayLinkDriving` boundary.
2. Keep all `CADisplayLink`, proxy, main-run-loop scheduling, pause, and
   invalidation behavior inside the system driver.
3. Preserve explicit uninstalled, idle, active, and closed driver phases with
   atomic diagnostics.
4. Add an `IRAVPlayerPresentationLoop` with explicit uninstalled, idle, active,
   and closed phases.
5. Bind every active presentation generation to one
   `IRAVPlayerSession.Token`.
6. Deliver immutable tick values containing the presentation token, session
   token, and timestamp.
7. Revalidate the presentation token before and after pixel-buffer acquisition
   so replacement, reset, or close rejects stale work.
8. Keep normal playback idle and activate polling only for VR.
9. Make deactivate reusable, close terminal and repeatable, and off-main
   invalidation safe.
10. Remove the raw display link, proxy, and dead `hasPixelBuffer` flag from
    `IRAVPlayer`.
11. Replace tests that inspect UIKit timer internals with deterministic driver
    and owner diagnostics.
12. Add driver, owner, lifecycle, failure, stale-tick, lifetime, and
    concurrency coverage.

## Non-Goals

- Changing `IRAVPlayerSession` ownership of AVFoundation resources.
- Changing `AVPlayerLayer` attachment ownership.
- Changing video-output pixel attributes or advance interval.
- Changing playback, buffering, seeking, track, or error policy.
- Adding display-link polling to normal playback.

## Shared Display-Link Driver

The shared driver exposes:

```text
phase: uninstalled | idle | active | closed
scheduledMode: RunLoop.Mode?
install(handler(timestamp)) -> Bool
setActive(Bool) -> Bool
close() -> Bool
```

The system implementation owns the concrete `CADisplayLink` and weak proxy.
Installation is main-thread-only, schedules the link in common run-loop modes,
and starts paused. Activation is main-thread-only. Close publishes the
terminal phase before invalidation and dispatches invalidation to the main
queue when called elsewhere.

The driver captures its handler under lock and invokes it after unlocking.
Only active-phase ticks are delivered. The display link does not retain the
driver through its proxy.

Smooth scrolling depends on this shared interface without changing its
animation state or timing behavior.

## AVPlayer Presentation Loop

The owner stores:

```text
phase: uninstalled | idle | active | closed
generationCounter: UInt64
activePresentationToken: Token?
activeSessionToken: IRAVPlayerSession.Token?
tickHandler: ((Tick) -> Void)?
driver: IRDisplayLinkDriving
```

`install` installs the driver exactly once and publishes idle only after
successful installation.

`activate(sessionToken:)` first activates the driver, then publishes a new
presentation generation bound to that exact session token. A tick cannot enter
the owner between driver activation and state publication; such an early tick
is safely ignored.

`deactivate` revokes the current presentation generation before pausing the
driver. This ordering makes an already queued native callback inert even if
UIKit delivers it after the mode switch.

`close` publishes closed, clears the handler and identities, then closes the
driver. All mutating operations share a serialization lock; tick admission and
diagnostics use a separate state lock so handlers never run under owner locks.

## Tick Admission And Rendering

An admitted tick is an immutable value:

```text
presentation token
AVPlayer session token
display-link timestamp
```

`IRAVPlayer` accepts it only when:

1. the presentation loop still owns both identities;
2. `IRAVPlayerSession` still owns the session token;
3. pixel-buffer lookup succeeds for resources with that exact token; and
4. both identities are still current immediately before render submission.

Normal-mode replacement and `replaceEmpty()` deactivate the loop before
detaching display resources. VR activation occurs only after the new
AVFoundation session token exists. Deinitialization closes the presentation
loop before closing the AVFoundation session.

## Verification

Focused tests must prove:

- shared driver installation, common-mode scheduling, active-only delivery,
  duplicate rejection, off-main rejection, close, and weak lifetime;
- loop install success/failure, exact active identity, repeatable deactivate,
  terminal close, and driver failure rollback;
- stale ticks are rejected after deactivate, replacement, reactivation, and
  close;
- callbacks and lifecycle mutation are race-free under Thread Sanitizer;
- normal playback stays idle and VR playback activates the loop;
- reset returns the loop to idle and backend release closes it;
- no raw AVPlayer display-link/proxy field or feature-specific system driver
  remains; and
- smooth-scroll behavior remains unchanged on the shared driver.

AVPlayer/facade/display integration, the full simulator suite, and a generic
iOS device build remain release gates.
