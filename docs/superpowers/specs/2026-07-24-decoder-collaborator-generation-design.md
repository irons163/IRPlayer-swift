# Decoder Collaborator Generation Design

## Summary

`IRFFDecoder` coordinates several worker threads but stores its delegate,
custom source, video output, and audio output as independent weak properties.
The player session publishes and clears those properties one at a time while
open, read, decode, display, and audio callback work can access them
concurrently.

Replace the independent bindings with one synchronized
`IRFFDecoderCollaboratorSession`. A complete collaborator generation contains
all four weak bindings, is installed before `open()`, and is revoked
terminally before decoder resource teardown. Video delivery is serialized with
revocation so no old frame can reach an output after generation detachment
returns.

## Problems

- Delegate, source, video output, and audio output are read and written without
  one synchronization domain.
- Player activation assigns output references in the factory, then source and
  delegate separately.
- Replacement clears four properties independently, exposing partial states.
- Display work can capture an old video output while replacement rebinds the
  same view or custom input to a new generation.
- Source detachment must also reach the installed `IRFFVideoDecoder`; the
  orchestrator and child currently coordinate through separate operations.
- Direct `IRFFDecoder.closeFile()` does not itself revoke collaborators.
- Tests inspect properties but do not prove atomic installation, terminal
  revocation, stale-frame exclusion, reentrancy, or concurrent replacement.

## Goals

- Own all external decoder collaborators in one focused synchronized session.
- Publish delegate, source, video output, and audio output as one generation.
- Keep every binding weak so the decoder never owns the player, input, display,
  or audio target.
- Allow a complete generation to replace the constructor's initial bindings
  before opening or during legacy decoder adoption.
- Make revocation terminal, idempotent, and all-or-nothing.
- Reject every update and delivery after revocation.
- Serialize video delivery with revocation: once `revoke()` returns, no prior
  output receives another frame.
- Keep delegate callbacks reentrant and rely on the player session's token
  bridge to reject already-captured stale events.
- Snapshot audio output references under collaborator synchronization, then
  read their values outside the lock to avoid crossing into the player
  executor while holding decoder state.
- Propagate source install/update/revoke to an installed video decoder without
  an install race.
- Make `closeFile()` revoke collaborators even for direct decoder users.
- Preserve public playback and custom-input behavior.

## Non-Goals

- Change decoder runtime state, queue ownership, packet/frame behavior, or
  playback timing.
- Replace the `IRFFPlayerDecoderSession` generation/token model.
- Make external delegate or output implementations thread-safe.
- Hold the collaborator lock across arbitrary delegate callbacks.
- Change the weak ownership contract to retain outputs.
- Change AVPlayer collaborator ownership.

## Components

### `IRFFDecoderCollaboratorSession`

The session has explicit `active` and `revoked` phases. It stores weak
references to:

- `IRFFDecoderDelegate`;
- `IRFFVideoDecoderDataSource`;
- `IRFFDecoderVideoOutput`; and
- `IRFFDecoderAudioOutput`.

`install(_:)` atomically replaces all four active bindings and increments the
generation. It fails after revocation. Individual compatibility setters update
one field only while active.

`revoke()` atomically enters the terminal phase and clears every binding.
Repeated revocation is inert.

Diagnostics expose phase, generation, installed binding presence, install and
revoke counts, accepted/rejected frame-delivery counts, and rejected update
counts.

### Delivery Semantics

Delegate access returns a synchronized strong snapshot, then calls outside the
session lock. Reentrant player commands remain safe, and the existing
generation-owned `DelegateBridge` rejects a callback captured before
replacement.

Video delivery holds a recursive session lock across the optional output call.
Concurrent revocation therefore waits for an admitted call to finish, while a
reentrant stop on the same thread can revoke safely. No call can begin after
revocation.

Audio output channel/rate reads use a synchronized strong snapshot and execute
the external getter outside the session lock. This preserves weak ownership
without creating a collaborator-lock/player-executor inversion. Source
snapshots are synchronized.

### Decoder Integration

`IRFFDecoder` owns one collaborator session whose recursive gate coordinates
collaborator source changes with child decoder installation:

- player activation installs the complete generation before `open()`;
- legacy adoption replaces the complete generation with the token bridge while
  preserving current source/output bindings;
- opening installs a video decoder with the current source inside one
  collaborator snapshot operation;
- later source updates and terminal revocation update the installed child
  through `IRFFDecoderSession`; and
- `closeFile()` revokes before scheduling teardown.

Every delegate and output call site consumes the collaborator owner rather than
reading a weak property directly.

### Player Session Integration

`IRFFPlayerDecoderSession.activate` constructs the delegate bridge, installs
the full collaborator generation, publishes the owned decoder generation, and
only then opens the decoder.

Drain and unpublished-discard paths call one `revokeCollaborators()` operation
instead of clearing four fields. Seek cancellation and decoder close ordering
remain unchanged.

## Invariants

- A player-owned decoder is never opened with a partially installed
  collaborator generation.
- Collaborators are weak and never extend target lifetime.
- Revocation clears all four bindings atomically and is terminal.
- No video frame delivery starts after revocation.
- Concurrent revocation waits for every earlier video delivery to finish.
- Reentrant revocation from an admitted video callback marks the generation
  terminal immediately; that callback may then unwind, and no later delivery
  can begin.
- Delegate callbacks remain reentrant and stale captured bridges are rejected
  by player generation identity.
- Source publication/revocation cannot race child decoder installation.
- Direct close and player-session drain both revoke collaborators.
- Post-revoke compatibility writes cannot resurrect a decoder generation.

## Testing

- Initial, complete install, replacement, diagnostics, weak lifetime, and
  terminal revocation.
- Concurrent getters, complete installs, individual updates, and revocation.
- Video delivery admitted before revoke, revoke waiting, and post-revoke
  rejection.
- Reentrant revoke from a video output callback.
- Delegate snapshot reentrancy and stale player bridge rejection.
- Audio snapshots do not retain the collaborator lock while crossing into an
  output getter.
- Source propagation during child installation and teardown.
- Direct close revocation and repeatability.
- Player activation, adoption, reentrant replacement, unpublished discard,
  reset, close, seek, and deinit integration.
- Thread Sanitizer coverage across collaborator/session/player boundaries.

## Acceptance Criteria

- `IRFFDecoder` contains no independently stored delegate/source/video/audio
  weak properties.
- Player activation and adoption install complete collaborator generations.
- Teardown contains one collaborator revoke rather than per-property clearing.
- A deterministic test proves no stale video delivery after revoke returns.
- Focused tests, Thread Sanitizer, the full simulator suite, and a generic iOS
  device build pass.
