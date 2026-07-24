# Decoded Frame Transport Ownership Design

## Context

`IRFFFrame`, `IRFFFramePool`, and `IRFFFrameQueue` form one ownership boundary:
decoders lease mutable frame objects from a pool, queues transfer those objects
between decode and presentation threads, and the renderer returns them through
frame lifecycle callbacks.

The current implementation protects some mutations but does not publish one
coherent lifecycle:

- pool buckets are mutated under `NSLock`, while their counts and frame
  identities remain directly readable without that lock;
- any class-compatible frame can be inserted into a pool even when that pool
  never created it;
- factories can publish an incompatible or duplicate object;
- the pool has no terminal phase, so decoder teardown only flushes and later
  work can lease again;
- synchronous dequeue polls every 5 ms instead of waiting for a producer or
  terminal close;
- queue accounting is calculated again from mutable frame fields at removal,
  so changing a frame after admission corrupts duration and byte totals;
- size and duration accumulation can overflow;
- flush, close, and rejected admission silently discard queue ownership
  without notifying a pooled frame to return;
- frame delegate and playing-state access are not synchronized even though
  callbacks cross decoder, display, and real-time audio threads; and
- three forwarding policy files split frame-time, pool, and queue semantics
  away from the values and owners that enforce them.

The 2.0 boundary should make ownership transfer explicit and leave every
observable snapshot internally coherent.

## Goals

1. Give `IRFFFrame` one synchronized transport/lifecycle value containing its
   delegate, playing flag, position, duration, and size.
2. Internalize the frame delegate so external clients cannot replace the
   pool's return path.
3. Give `IRFFFramePool` explicit open and closed phases with atomic
   diagnostics.
4. Track only pool-created frame identities and maintain an exact partition of
   available, leased, and playing frames.
5. Reject incompatible, duplicate, foreign, and post-close pool operations.
6. Give `IRFFFrameQueue` explicit open and closed phases with atomic
   diagnostics and repeatable terminal close.
7. Capture immutable position, accounted duration, and accounted size when a
   frame is admitted.
8. Use condition signalling for synchronous dequeue, with close waking every
   waiter immediately.
9. Define queue admission as an ownership transfer and return an explicit
   result for accepted, invalid, duplicate, overflow, and closed requests.
10. Return consumed frames on flush, close, or ownership-retaining rejection by
   invoking `cancel()` outside the queue lock.
11. Make decoder destroy close both transport owners and prevent late decode
    work from republishing a frame.
12. Consolidate frame-time, pool, and queue semantics beside their domain
    owners and remove the three forwarding policy files.
13. Add deterministic lifecycle, failure, blocking, immutable-accounting,
    overflow, integration, and concurrency coverage.
14. Assign decoder worker QoS by producer/consumer role so blocking packet and
    frame consumers cannot create a priority inversion.

## Non-Goals

- Rewriting decoded PCM or I420 plane storage, which already have managed
  storage owners.
- Changing FFmpeg packet ownership or packet-queue control items.
- Changing audio sample format, video timing formulas, or display
  frame-selection policy.
- Adding a fixed maximum pool capacity. Existing `capacity` remains an
  allocation-reservation hint rather than a hard limit.
- Making a frame safe for arbitrary simultaneous payload mutation and render
  consumption. The queue remains the happens-before ownership-transfer
  boundary for subclass payloads.

## Frame Lifecycle Value

`IRFFFrame` keeps one private lock around:

- weak delegate;
- playing state;
- position;
- duration; and
- size.

Public position, duration, and size remain source-compatible computed
properties. Delegate installation becomes an internal pool responsibility.
Queue admission obtains all transport metadata in one locked snapshot.

`startPlaying`, `stopPlaying`, and `cancel` update state and capture the
delegate while locked, then invoke the delegate after unlocking. This prevents
lock inversion with the pool. `prepareForReuse` clears playing state and all
transport metadata without a callback.

Frame timestamps move directly into `IRFFFrameTime`; invalid timestamps,
timebases, and overflow continue to produce zero.

## Pool State

The pool owns:

```text
phase: open | closed
ownedFrames: ObjectIdentifier -> IRFFFrame
availableIDs: Set<ObjectIdentifier>
leasedIDs: Set<ObjectIdentifier>
playingID: ObjectIdentifier?
revision: UInt64
```

For an open pool, every owned identity appears in exactly one lifecycle bucket.
Diagnostics are captured while holding the pool lock and expose phase, bucket
counts, total ownership, and revision without exposing mutable collections.

Acquisition first reuses an available frame. When allocation is required, the
factory result must:

- be compatible with the configured frame class;
- not already be owned by the pool; and
- still be publishable while the pool remains open.

The factory executes outside the pool lock and behind its own serialization
lock, so an injected factory cannot block or re-enter the state owner and does
not need to be concurrently callable. Publication and delegate installation
happen under the state lock.

Only owned leased frames may enter playing state. Stopping or cancelling an
owned frame returns it to available exactly once. Starting a new owned frame
returns the previous playing frame before publishing the new playing identity.
Foreign and duplicate callbacks are inert.

`flush()` is reusable and returns leased and playing frames to available.
`close()` is terminal and repeatable: it clears all buckets and ownership,
detaches delegates, and prevents later allocation or callback publication.

## Queue Entries And Admission

Each admitted frame becomes one immutable queue entry:

```text
frame identity
frame reference
captured position
captured accounted duration
captured accounted size
monotonic insertion sequence
```

The queue owns each identity at most once. Sorted admission orders finite
positions ascending, keeps equal positions stable, and places non-finite
positions after finite positions in insertion order. Later frame mutation
cannot change order or accounting.

Admission returns a typed result:

- `accepted`;
- `rejectedNil`;
- `rejectedDuplicate`;
- `rejectedAccountingOverflow`; or
- `rejectedClosed`.

Nil and duplicate requests do not create a new ownership token. Overflow and
closed rejection retain the caller's offered ownership, so the queue cancels
that frame after releasing its condition lock. This returns pooled objects
without executing arbitrary delegate code under the queue lock.

Size addition uses checked integer arithmetic. Duration addition must remain
finite. An admission that would make either aggregate unrepresentable is
rejected before mutation.

## Waiting, Flush, And Close

Synchronous dequeue waits in the standard condition loop:

```text
while queue is open and empty:
    wait
```

Admission signals one waiter. Terminal close broadcasts to all waiters.
Spurious wakeups are harmless because phase and emptiness are rechecked under
the same condition lock.

Dequeue removes using captured accounting. Flush drains and cancels all queued
entries but leaves the queue open. Close drains and cancels all entries,
publishes the terminal phase once, and wakes every waiter. Deinitialization
performs the same terminal drain.

## Decoder Integration

Audio and video decoder `destroy()` operations close the frame queue before
closing the pool:

1. queue close drains queued objects back through `cancel()`;
2. pool close detaches every remaining owned frame; and
3. late decode or external-output admission is rejected and returned.

Reusable decoder `flush()` remains queue flush followed by pool flush.

The read worker remains user-initiated because it supplies the pipeline.
Decode and display are default-QoS blocking consumers of the packet and frame
queues respectively. Explicitly naming and configuring these roles avoids
raising a waiter above the thread that must satisfy its condition.

## Verification

Focused tests must prove:

- coherent frame metadata and lifecycle callbacks;
- exact pool bucket transitions and reuse;
- incompatible, duplicate-factory, foreign-frame, and closed-pool rejection;
- repeatable flush and close;
- immutable queue accounting and ordering after frame mutation;
- checked overflow rejection;
- immediate producer wake and close wake for synchronous consumers;
- drain cancellation outside queue mutation;
- duplicate and post-close admission semantics;
- audio/video decoder destroy unblocks fetch and rejects late work;
- decoder worker roles avoid packet/frame condition priority inversions;
- concurrent pool lifecycle and queue mutation snapshots under Thread
  Sanitizer; and
- no policy or polling implementation remains.

The full simulator suite and generic iOS device build remain release gates.
