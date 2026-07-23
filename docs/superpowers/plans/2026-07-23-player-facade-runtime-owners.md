# Player Facade Runtime Owners Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-23-player-facade-runtime-owners-design.md`.

## Phase 1: Backend And State Boundaries

- [x] Serialize `IRPlaybackBackendCoordinator` ownership and commands.
- [x] Add diagnostics and concurrent replacement/reset coverage.
- [x] Add kind-gated backend event routing and host adapters.
- [x] Add synchronized settings/error and media-source sessions.
- [x] Make source replacement a post-stop coordinator transaction.

## Phase 2: Presentation Owner

- [x] Add `IRPlayerPresentationSession` as the display host/delegate.
- [x] Move render modes, gravity, view attachment/frame, gesture, scroll, and
  sensor ownership out of the facade.
- [x] Wire single tap and selected render mode correctly.
- [x] Replace the nil snapshot stub with display capture.
- [x] Add terminal/idempotent presentation teardown.

## Phase 3: Environment Owner

- [x] Add `IRPlayerEnvironmentSession` with injected notification center,
  clock, command dispatcher, audio manager, and idle timer.
- [x] Replace selector app observers with exact block tokens.
- [x] Synchronize background/foreground/audio lifecycle decisions.
- [x] Support safe audio-manager replacement/removal.
- [x] Move lifecycle decisions into `IRPlayerLifecycleController` and remove
  `IRPlayerLifecyclePolicy`.

## Phase 4: Facade Integration And Tests

- [x] Reduce `IRPlayerImp` to public API forwarding and owner composition.
- [x] Keep typed/legacy event compatibility through the gated event sink.
- [x] Add invalid-source/backend-unavailable cleanup tests.
- [x] Add custom-input replacement ordering and binding tests.
- [x] Add mode selection, tap, snapshot, environment cleanup, and idle-timer
  tests.
- [x] Add stale-event and concurrent command/replacement tests.
- [x] Update Xcode project membership and owner documentation.

## Phase 5: Verification

- [x] Run expanded player facade/backend/presentation/environment suites.
- [x] Run affected suites with Thread Sanitizer.
- [x] Run full iOS Simulator suite.
- [x] Run generic iOS device build.
- [x] Run project validation and `git diff --check`.
- [x] Update the 2.0 completion audit and create a focused commit.

## Baseline

- Existing facade/API/coordinator/lifecycle/render/event/notification focused
  suites: 48 passed, 0 failed, 0 skipped.

## Completion

- Expanded facade/runtime-owner suites: 75 passed, 0 failed, 0 skipped.
- Full iOS Simulator suite: 1036 passed, 0 failed, 0 skipped.
- Thread Sanitizer facade/runtime-owner suites: 75 passed, 0 failed, no race
  diagnostics.
- Generic iOS device build: passed.
- Xcode project list/plist validation, Swift package manifest description, and
  `git diff --check`: passed.
