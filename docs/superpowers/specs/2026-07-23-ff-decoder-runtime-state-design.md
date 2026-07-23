# FFmpeg Decoder Runtime State Design

## Summary

`IRFFDecoder` currently coordinates four independently scheduled callers:

- packet reading;
- video decoding and display;
- the real-time audio consumer;
- public playback, seek, and close commands.

Those callers read and mutate playback flags, clocks, buffered time, pending
seek work, and current frames directly on `IRFFDecoder`. The loop-policy types
make individual decisions testable, but they do not make the shared runtime
state safe.

This change introduces `IRFFDecoderRuntimeState` as the single synchronized
owner of decoder session state. `IRFFDecoder` remains the orchestration facade
and owns FFmpeg resources and delegate delivery. Thread Sanitizer validation
also brought the adjacent video-decoder runtime flags and packet/frame queue
accounting into their existing synchronization boundaries.

## Goals

- Make decoder status snapshots coherent across read, display, audio, control,
  and close threads.
- Make close idempotent under concurrent callers.
- Make pending seek replacement and consumption deterministic.
- Protect current audio and video frame references.
- Protect packet/frame queue contents and all derived accounting with the same
  queue lock.
- Make video-decoder cancellation, EOF, pause, decoding, error, and runtime
  configuration reads race-free.
- Keep locks private to the state owner and never invoke callbacks while a lock
  is held.
- Preserve existing decoder behavior and delegate semantics.
- Add deterministic unit tests for state transitions and concurrent access.

## Non-Goals

- Replace `OperationQueue` or the packet/frame queue data structures.
- Hold the runtime-state lock while calling FFmpeg, delegates, or video/audio
  outputs.
- Change packet timing, buffering thresholds, or rendering algorithms.
- Make vendored FFmpeg C types conform to Swift concurrency protocols.

## State Boundary

`IRFFDecoderRuntimeState` owns:

- progress and buffered duration;
- buffering, playback-finished, closed, EOF, paused, seeking, prepared, and
  reading flags;
- audio clock and buffering start time;
- live-stream and buffer configuration used by worker threads;
- the latest error presence/value;
- pending seek target and completion callback;
- current audio and video frames.

It exposes immutable scalar snapshots plus focused mutation methods. Reference
types and callbacks are returned as strong local values after releasing the
lock.

`IRFFVideoDecoder` keeps its smaller worker state behind one private lock and
reads coherent snapshots in the decode loop. `IRFFPacketQueue` and
`IRFFFrameQueue` protect their collection, count, byte size, and duration with
their existing `NSCondition`; locked code reads stored values directly to avoid
recursive locking.

## Seek Semantics

Starting a seek atomically stores the target, completion callback, seeking flag,
and visible progress. A newer seek displaces an older pending completion; the
caller completes the displaced request with `false` outside the lock.

The packet loop atomically consumes one pending seek. Its completion callback is
also invoked outside the lock.

Closing a decoder cancels any pending seek exactly once with `false`.

## Close Semantics

`beginClose()` performs the closed check-and-set atomically and returns whether
the caller owns cleanup. Only that caller destroys decoders, waits for
operations, destroys the format context, and clears resources. Repeated or
concurrent close requests are no-ops.

## Acceptance Criteria

- Runtime scalar state and current frame references are no longer stored as
  unsynchronized mutable properties on `IRFFDecoder`.
- Public status access remains source compatible.
- Concurrent `beginClose()` calls elect exactly one cleanup owner.
- Concurrent snapshot reads and mutations complete without inconsistent
  compound states or crashes.
- Replaced and cancelled seek callbacks execute exactly once and outside the
  state lock.
- Thread Sanitizer passes real decoder operation tests and concurrent state and
  queue stress tests.
- Existing focused FFmpeg tests and the full iOS Simulator suite pass.
