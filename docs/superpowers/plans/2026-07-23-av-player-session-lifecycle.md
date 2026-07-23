# AVPlayer Session Lifecycle Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-23-av-player-session-lifecycle-design.md`.

## Phase 1: Session Owner

- [x] Add `IRAVPlayerSession` with repeatable phases and generation tokens.
- [x] Build and atomically publish asset/item/player resources.
- [x] Own typed KVO, notification, and periodic-time tokens.
- [x] Add resource leases, output-rebuild fencing, reset, and silent close.
- [x] Add current-token checks for asset, item, and player callbacks.

## Phase 2: Backend Integration

- [x] Route playback, metadata, snapshot, pixel-buffer, and track access through
  session resources.
- [x] Route observation and periodic-time events through typed session events.
- [x] Generation-gate VR asset loading, seek completion, and delayed play retry.
- [x] Restrict video output/display-link work to VR sessions.
- [x] Attach normal playback to a real display-owned `AVPlayerLayer` and detach
  it for VR/reset/close.
- [x] Split lifecycle, presentation, and track behavior out of the command/state
  facade.
- [x] Remove direct AV resource properties, manual KVO, and split cleanup
  methods from `IRAVPlayer`.
- [x] Remove the superseded asset-load/redirect policy file.
- [x] Make deinit silently close resources without host callbacks.

## Phase 3: Tests

- [x] Add activation/observation ownership tests.
- [x] Add reset/close idempotence and complete resource-drain tests.
- [x] Add stale generation/event rejection tests.
- [x] Add reset-waits-for-lease and output-rebuild tests.
- [x] Add backend replacement, seek, retry, and renderer-mode regressions.
- [x] Update AVPlayer tests to use the session boundary.

## Phase 4: Verification

- [x] Run session and AVPlayer focused suites.
- [x] Run affected lifecycle suites with Thread Sanitizer.
- [x] Run `git diff --check` and Xcode project validation.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Update the 2.0 completion audit and create a focused commit.

## Verification Results

- Focused AVPlayer/session suites: 75 passed, 0 failed.
- Thread Sanitizer AVPlayer/session suites: 75 passed, 0 failed, no race
  diagnostics.
- Full iOS Simulator suite: 969 passed, 0 failed, 0 skipped. An initial result
  bundle finalization encountered a full-disk error after all tests passed; a
  clean formal rerun also passed 969/969.
- Generic iOS device build: passed.
- Xcode project plist validation and `git diff --check`: passed.
