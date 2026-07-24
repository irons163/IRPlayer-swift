# Photo Library Transaction Ownership Design

## Summary

`IRPhotoSaver` currently launches a chain of static Photos calls without
owning the request after it starts. The caller cannot observe success or
failure, duplicate or reentrant callbacks can repeat side effects, concurrent
requests can race to create the same album, and there is no terminal teardown
boundary. The existing `IRPhotoSaverPolicy` only exposes wrappers around a few
pure decisions and does not make the asynchronous workflow testable.

Replace the static workflow with an `IRPhotoLibrarySession`. Each save is an
explicit, generation-identified transaction that moves through authorization,
album resolution, optional album creation, and asset saving. A driver isolates
Photos framework objects behind value identifiers so tests can exercise every
callback ordering without accessing the real photo library.

## Problems

- Static Photos calls have no owner, request identity, result, diagnostics, or
  close behavior.
- Permission, album creation, and asset-write failures are silently discarded.
- A driver callback invoked more than once can repeat downstream work.
- Concurrent requests for one missing album can independently create it.
- Photos objects and callbacks are embedded directly in orchestration code.
- No test covers the asynchronous save workflow or exactly-once completion.
- `IRPhotoSaverPolicy` is a separate policy file whose decisions belong to the
  saver value model and transaction owner.

## Goals

- Give every save request one immutable token and one owned state-machine
  entry.
- Publish request state before invoking any external driver operation so
  synchronous and reentrant callbacks are safe.
- Admit each callback only from its expected stage.
- Deliver exactly one terminal outcome per accepted request.
- Prevent duplicate callbacks from repeating album creation, asset writes, or
  completion delivery.
- Coalesce concurrent creation of the same missing album and fan the result
  out to all waiting transactions.
- Keep Photos framework objects inside the system driver; the session exchanges
  authorization statuses and album identifiers only.
- Call every external driver method and client completion outside the session
  lock.
- Make close terminal and idempotent, cancel all pending transactions once,
  and reject later saves.
- Preserve the existing fire-and-forget `IRPhotoSaver.save` call shape.
- Remove `IRPhotoSaverPolicy` and keep pure decisions with `IRPhotoSaver`.

## Non-Goals

- Add a new public player API or change snapshot capture scheduling.
- Persist album identifiers across process launches.
- Retry denied authorization or failed Photos changes automatically.
- Cancel a Photos framework change after it has already been submitted.
- Guarantee the callback queue used by an injected driver.

## Components

### `IRPhotoSaver`

`IRPhotoSaver` remains the compatibility facade and owns:

- `Failure`, `Outcome`, and `Destination` values;
- authorization and album-name normalization;
- optional diagnostic text; and
- the process-wide system session used by existing fire-and-forget callers.

An internal completion-bearing overload exposes terminal outcomes for owned
callers and tests without changing the existing call sites.

### `IRPhotoLibraryDriving`

The driver boundary has four operations:

- request read/write authorization;
- find an album identifier by name;
- create an album and return its identifier; and
- save an image to the library or an identified album.

`IRSystemPhotoLibraryDriver` is the only component that handles
`PHAssetCollection`, `PHAssetChangeRequest`, placeholders, and
`PHPhotoLibrary.performChanges`.

### `IRPhotoLibrarySession`

The session has `active` and `closed` phases. A pending request owns its image,
destination, stage, and completion. Stages are:

1. requesting authorization;
2. resolving an album;
3. waiting for album creation; and
4. saving the asset.

Every callback validates its token and expected stage while holding the lock,
records the next state, then invokes follow-up work after unlocking.

Missing-album creation is keyed by normalized album name. The first request
starts creation and later requests join its waiter list. One creation result
advances or fails every still-admitted waiter.

Diagnostics expose phase, pending count, total requests, successes, failures,
cancellations, rejected requests, album creations, coalesced album requests,
and ignored stale/duplicate callbacks.

## Close Semantics

`close()` enters the terminal phase, removes every pending request and album
waiter, records cancellation counts, and delivers one cancelled outcome per
request outside the lock. Repeated close is inert. Later driver callbacks only
increment the ignored-callback count. A save attempted after close returns no
token and completes once with `.closed`.

Deinitialization silently invalidates pending state without executing arbitrary
client code.

## System Driver Semantics

The system driver:

- treats `.authorized` and `.limited` as granted;
- fetches existing albums by exact normalized title;
- captures album identifiers and change configuration through synchronized
  storage shared by the Photos change and completion blocks;
- fails an album save if the identifier no longer resolves; and
- reports success only when the requested Photos change was fully configured
  and committed.

## Invariants

- One accepted token has at most one active stage and exactly one terminal
  outcome while its session remains owned.
- No external driver or completion closure executes while the session lock is
  held.
- Duplicate, stale, out-of-order, and post-close callbacks cannot start a new
  downstream operation.
- At most one album-creation operation is active per normalized album name.
- An image is retained only while its request is pending.
- Close clears every pending image and completion atomically.
- Fire-and-forget callers continue to receive silent default behavior while
  failures remain available to diagnostics and completion-bearing callers.

## Testing

- Authorization normalization and album-name normalization.
- Permission rejection without album or save work.
- Library save success and failure.
- Existing-album save success.
- Album creation success, missing identifier, and failure.
- Concurrent missing-album requests coalesce one creation and all save.
- Synchronous/reentrant callbacks are accepted after state publication.
- Duplicate authorization, creation, and save callbacks do not duplicate side
  effects or completions.
- Close cancellation, repeated close, post-close rejection, and late callback
  rejection.
- Concurrent request/callback/close behavior under Thread Sanitizer.
- Snapshot-session integration remains unchanged.

## Acceptance Criteria

- `IRPhotoSaver` no longer directly orchestrates an unowned Photos callback
  chain.
- `IRPhotoSaverPolicy.swift` is removed.
- Every accepted request has a token, explicit stage, observable outcome, and
  deterministic diagnostics.
- Duplicate callbacks cannot repeat a Photos save.
- Concurrent creation of one album is coalesced.
- Focused tests, Thread Sanitizer, the full simulator suite, and a generic iOS
  device Release build pass.
