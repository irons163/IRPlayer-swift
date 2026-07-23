# FFmpeg Decoder Session Lifecycle Design

## Summary

`IRFFDecoder` currently stores its `OperationQueue`, four operation references,
format context, and audio/video decoders as unrelated optional properties.
Opening, worker scheduling, external metadata/audio access, and asynchronous
close therefore depend on ordering conventions rather than one enforceable
lifecycle.

This change introduces `IRFFDecoderSession` as the single owner of those
resources. It owns the session phase, operation dependency graph, resource
installation, external resource leases, cancellation fence, wait order, and
final teardown.

## Problems

- `open()` can be called more than once or after close.
- Operation creation and asynchronous close are not synchronized.
- Format/decoder references are published and read without one ownership
  boundary.
- Close snapshots decoders before waiting, while an opening operation can still
  publish new resources.
- UI metadata getters and the audio callback are not fenced against format
  context destruction.
- Four operation helper functions live in a separate policy type even though
  scheduling is resource ownership, not a pure domain decision.
- The read loop contains an audio-track replacement branch with no caller or
  public/internal entry point.

## Goals

- Model decoder session phases explicitly: idle, opening, active, failed,
  closing, and closed.
- Schedule open/read/decode/display operations only through the session owner.
- Reject duplicate open, worker scheduling after close, and resource
  installation after close.
- Preserve the open operation as the dependency for every worker generation.
- Fence close against both queued operations and external resource users.
- Destroy decoder queues before waiting so blocked audio/video fetches can
  terminate.
- Wait for operations and external leases before destroying the format context.
- Keep FFmpeg calls and delegate callbacks outside the session lock.
- Remove unreachable audio-track selection state and the superseded operation
  policy.

## Non-Goals

- Change FFmpeg demux/decode algorithms, buffer thresholds, or render timing.
- Reopen a closed `IRFFDecoder`; a new media load creates a new backend decoder
  session.
- Make FFmpeg C pointers globally `Sendable`.
- Hold the session lock across `av_read_frame`, frame waits, delegate delivery,
  or resource destruction.

## Lifecycle

```text
idle --start--> opening --resources ready--> active
                    \--open error----------> failed

idle/opening/active/failed --close--> closing --fences complete--> closed
```

All transitions are performed under one `NSCondition`.

`start` installs and enqueues exactly one open operation. The session becomes
active only after format setup and decoder installation complete, so external
callers cannot observe partially initialized resources. Worker operations are
created only while opening or active, depend on that open operation, and may be
created again after a previous generation finishes (for EOF seek/resume).

## Resource Access

Two access forms are intentional:

- Session worker operations take a strong resource snapshot. Close waits for
  the operation queue before final resource destruction.
- External callers use `withResources`, which registers a lease before
  returning the snapshot and releases it after the caller's closure finishes.

External access is admitted only in active or failed phases. Opening returns the
caller's safe default; closing and closed reject new leases.

Close changes the phase to closing before taking its resource snapshot, so no
new operation, installation, or external lease can begin. It destroys decoder
queues to unblock frame waits, cancels and waits for operations, waits for
existing external leases, atomically drains references, and finally destroys
the format context outside the lock.

## Error And Close Semantics

- An open error marks the session failed and retains the partially constructed
  format context until close.
- A close racing with format-context creation either includes the installed
  context in teardown or causes installation to fail; the opening operation
  destroys a rejected local context.
- Concurrent close calls elect exactly one teardown owner.
- Resource access during closing/closed returns the caller's safe default.
- Runtime-state close remains the public idempotence gate; session close is an
  independent ownership invariant and is also idempotent.

## Policy Consolidation

`IRFFDecoderOperationPolicy` is removed. Operation eligibility, dependency
wiring, and enqueueing move into `IRFFDecoderSession`, their actual owner.
Error notification remains a direct decoder invariant (`error != nil &&
!closed`).

The unreachable `selectAudioTrack` fields and read-loop branch are removed.
`IRFFFormatContext` track-selection behavior remains covered independently and
can be exposed later through an explicit session command if required.

## Acceptance Criteria

- `IRFFDecoder` no longer stores OperationQueue/Operation or concrete
  format/audio/video resource properties.
- Duplicate/post-close open and post-close scheduling are rejected.
- Close waits for running operations and external leases, then releases all
  resources exactly once.
- Format context destruction cannot overlap a registered external resource
  access.
- Existing real audio/video decoder behavior remains green.
- New lifecycle, close-race, lease, and failure-path tests pass under Thread
  Sanitizer.
- Full iOS Simulator tests and a generic iOS device build pass.
