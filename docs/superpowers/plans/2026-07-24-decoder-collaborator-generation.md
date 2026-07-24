# Decoder Collaborator Generation Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-decoder-collaborator-generation-design.md`.

## Phase 1: Baseline and Owner

- [x] Audit collaborator construction, worker reads, replacement, adoption,
  direct close, and deinitialization.
- [x] Record the focused decoder/player baseline.
- [x] Add explicit collaborator phases, complete configuration, and
  diagnostics.
- [x] Store all bindings weakly behind one recursive synchronization domain.
- [x] Add atomic complete install and terminal idempotent revoke.

## Phase 2: Delivery and Decoder Integration

- [x] Route every delegate access through synchronized snapshots.
- [x] Serialize video delivery with revocation.
- [x] Route audio output reads and custom source access through the owner.
- [x] Coordinate child video-decoder source install/update/revoke.
- [x] Revoke collaborators at direct decoder close.

## Phase 3: Player Generation Integration

- [x] Install a complete collaborator generation before decoder open.
- [x] Preserve source/output bindings while installing an adoption bridge.
- [x] Replace per-property teardown with one terminal revoke.
- [x] Preserve seek cancellation, close ordering, and token-fenced events.
- [x] Update local architecture guidance.

## Phase 4: Tests

- [x] Cover install, replacement, weak ownership, diagnostics, and revocation.
- [x] Cover concurrent install/update/read/revoke behavior.
- [x] Prove revoke waits for admitted video delivery and rejects later frames.
- [x] Cover reentrant revoke from output and delegate callbacks.
- [x] Cover source propagation and post-close rejection.
- [x] Preserve activation, adoption, replacement, seek, reset, close, and
  playback integration.

## Phase 5: Verification

- [x] Run focused collaborator, decoder, session, player, and audio suites.
- [x] Run the changed boundary under Thread Sanitizer.
- [x] Run FFmpeg decode and player integration suites.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run metadata, stale-symbol, warning, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Decoder collaborator consumers, decoder/video/audio sessions, FFPlayer
  decoder-session owner, runtime, and facade suites: 125 passed, 0 failed, 0
  skipped.

## Focused Verification

- Collaborator owner, decoder operation, and decoder-session owner suites:
  48 passed, 0 failed, 0 skipped.
- Thread Sanitizer collaborator, decoder session, operation, audio/video
  decoder, FFPlayer decoder-session owner, runtime, and facade suites:
  136 passed, 0 failed, 0 skipped, with no race diagnostics.
- Full iOS Simulator suite: 1307 passed, 0 failed, 0 skipped.
- Generic iOS device Release build: passed. Changed project sources emit no
  warnings; Xcode only reports its expected AppIntents metadata notice.
