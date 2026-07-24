# VideoToolbox Session Ownership Design

## Summary

`IRFFVideoToolBox` currently stores a `VTDecompressionSession`, format
description, setup token, NAL conversion flag, callback status, and callback
image as unrelated mutable properties. The VideoToolbox callback receives an
unretained pointer to the facade itself, while `sendPacket`, `flush`, setup,
and teardown have no common execution or lifecycle boundary.

This change makes `IRFFVideoToolBox` a small decode facade over an explicit
session-generation owner and a synchronized callback context. The concrete
VideoToolbox resource generation is installed atomically, leased while used,
and drained before callback context release. H.264 validation and NAL parsing
remain pure domain algorithms but move out of the policy-per-type structure.

## Evidence

Apple documents that decode calls made without asynchronous or temporal decode
flags complete their output callback before `VTDecompressionSessionDecodeFrame`
returns. The current implementation relies on that behavior, but does not
encode it as an invariant. Apple also requires the client to invalidate a
decompression session when finished and defines the output `refCon` as the
client-provided callback reference.

The new design keeps synchronous decode behavior, explicitly serializes setup,
decode, reset, and close, retains the callback context for exactly the lifetime
of its installed session generation, and still waits for outstanding frames
before invalidation.

## Problems

- Setup publication is represented by a Boolean independent of the concrete
  session and format description.
- A callback uses `Unmanaged.passUnretained(self)` and mutates facade fields.
- Callback result fields are not synchronized.
- Flush can conceptually overlap setup or decode without an owner-enforced
  ordering.
- Partial setup failure cleanup is spread through `setupVTSession()`.
- Tests mutate implementation tokens directly to manufacture invalid states.
- `IRFFVideoToolBoxPolicy` duplicates the facade with one-to-one forwarding
  methods and obscures ownership.

## Goals

- Introduce explicit idle, setting-up, active, and closed phases.
- Publish only complete VideoToolbox resource generations.
- Reject stale setup completion after reset or close.
- Track active generation leases and drain them before teardown.
- Retain callback context until the matching session has waited and been
  invalidated.
- Store callback status and image atomically.
- Serialize public setup, decode, flush, and close operations.
- Keep flush repeatable and allow a later packet to build a new generation.
- Make close terminal and idempotent.
- Keep decode synchronous and preserve current software-decoder fallback
  behavior.
- Consolidate H.264/NAL algorithms beside the VideoToolbox domain.
- Add deterministic lifecycle, stale-generation, lease, callback, partial
  failure, and concurrent stress tests.

## Non-Goals

- Enable asynchronous or temporal VideoToolbox decoding.
- Change H.264-only hardware decode selection.
- Change packet timestamp or frame-duration behavior.
- Retain the FFmpeg codec context beyond its owning video decoder.
- Replace the FFmpeg software decode fallback.

## Components

### `IRFFVideoToolBox`

The facade owns:

- the borrowed codec-context pointer;
- one operation lock for setup/decode/reset/close ordering;
- an `IRFFVideoToolBoxSession<Generation>`;
- translation from FFmpeg packets to Core Media buffers.

It does not store independent session tokens, format descriptions, conversion
flags, or callback outputs.

### `IRFFVideoToolBoxSession<Resource>`

The generic internal owner models:

```text
idle --begin setup--> settingUp --install--> active
  ^                         \--cancel------/
  +-- resetting <--- reset <--- active

idle/settingUp/active --close--> closing --> closed
```

Setup tickets carry a monotonically increasing generation. Reset and close
invalidate outstanding tickets. Active resource access creates a lease. Reset
or close first enters a draining phase that blocks setup and new access, waits
for current leases, runs resource teardown exactly once, and only then publishes
idle or closed.

### `IRFFVideoToolBoxCallbackState`

The callback context stores status and image under one lock. Each synchronous
decode resets it before submission and reads one coherent result afterward.
The context is passed with `Unmanaged.passRetained` and released only after the
matching decompression session has waited for frames and been invalidated.

### H.264 Domain Algorithms

Setup validation, AVCC normalization, packet payload validation, bounded
three-byte NAL traversal, converted block ownership, and format-description
extensions remain stateless helpers on the VideoToolbox domain. The separate
`IRFFVideoToolBoxPolicy` type is removed.

## Setup And Failure Semantics

1. Admit one setup ticket.
2. Validate codec and AVCC data.
3. Normalize the three-byte NAL marker when needed.
4. Build a local format description.
5. Allocate and retain a local callback context.
6. Build a local decompression session.
7. Atomically install the complete generation.

Every failure cancels the ticket. Any locally created session is waited,
invalidated, and released together with its callback reference. If reset or
close invalidates the ticket before publication, installation is rejected and
the same local cleanup path runs.

## Decode Semantics

`sendPacket` holds the operation gate, ensures an active generation, validates
the packet, resets the generation callback result, builds the block/sample
buffers, and submits with empty decode flags. The callback therefore completes
before submission returns. Success requires:

- the submission status is `noErr`;
- callback status is `noErr`;
- a callback image exists.

The image is returned through `imageBuffer()` only while its generation remains
active and its callback result is successful.

## Reset And Close

- `flush()` is repeatable. It drains the active generation, waits for frames,
  invalidates the session, clears callback output, releases callback context,
  and returns the owner to idle.
- `close()` performs the same drain but transitions terminally to closed.
- `deinit` calls terminal close.
- A stale setup ticket cannot publish after either reset or close.

## Testing

- Generic session-owner tests use simple fake resources and do not require
  hardware decode availability.
- Callback-state tests cover coherent reset, publish, snapshot, and concurrent
  access.
- Facade tests continue covering validation, NAL bounds, Core Media payload
  construction, real session creation when available, packet rejection,
  callback delivery, flush, and release.
- Concurrent facade setup/reset/image access is run under Thread Sanitizer.

## Acceptance Criteria

- `IRFFVideoToolBox` has no independent mutable session token, format
  description, NAL-conversion flag, callback status, or callback image fields.
- Callback code never dereferences an unretained `IRFFVideoToolBox`.
- Complete generations are installed atomically and drained exactly once.
- Reset permits later setup; close permanently rejects setup.
- Stale setup completion is rejected after reset and close.
- Active leases finish before resource drain returns.
- Callback result reads and writes are synchronized.
- `IRFFVideoToolBoxPolicy.swift` is removed.
- Focused tests and their Thread Sanitizer run pass.
- Full simulator tests and a generic iOS device build pass.
