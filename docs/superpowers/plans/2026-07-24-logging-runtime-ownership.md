# Logging Runtime Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-logging-runtime-ownership-design.md`.

## Phase 1: Audit and Baseline

- [x] Inventory mutable logger globals, delegate access, sinks, and call sites.
- [x] Inventory FFmpeg and Metal logging/debug policy wrappers.
- [x] Record the focused logger, FFmpeg-tools, and Metal baseline.

## Phase 2: Logging Owner

- [x] Add explicit logging-session phase and immutable diagnostics.
- [x] Synchronize weak delegate and configuration generations.
- [x] Deliver delegate and fallback callbacks outside the lock.
- [x] Add reentrant-safe emission and terminal repeatable close.
- [x] Prevent logger/session retain cycles.

## Phase 3: Public and Runtime Integration

- [x] Replace unsafe static storage with computed session accessors.
- [x] Publish coherent subsystem/default-logger replacements.
- [x] Preserve explicit library-logger replacement and public logger API.
- [x] Route enabled FFmpeg and Metal diagnostics through the library logger.
- [x] Keep disabled message autoclosures lazy and silent.
- [x] Consolidate variadic FFmpeg formatting beside `IRFFTools`.
- [x] Remove the three forwarding-only logging policy files and project entries.
- [x] Update local architecture guidance.

## Phase 4: Tests

- [x] Cover every severity, exact category, and fallback behavior.
- [x] Cover weak delegate lifetime and strong per-emission snapshot.
- [x] Cover reentrant logging and delegate replacement outside the lock.
- [x] Cover coherent subsystem and explicit logger replacement.
- [x] Cover close, post-close rejection, and silent deinitialization.
- [x] Cover concurrent configuration, delegate, emission, and close.
- [x] Preserve disabled FFmpeg/Metal and variadic-format behavior.
- [x] Preserve frame-pool and public source compatibility.

## Phase 5: Verification

- [x] Run focused logging, FFmpeg-tools, Metal, and frame-pool suites.
- [x] Run the logging boundary under Thread Sanitizer.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run project, stale-symbol, warning, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Logger compatibility, FFmpeg tools, Metal pixel renderer, and frame-pool
  suites: 85 passed, 0 failed, 0 skipped.
- Result bundle: `/private/tmp/irplayer-logging-baseline.xcresult`.

## Results

Recorded on 2026-07-24 after implementation:

- Focused logger, compatibility, FFmpeg tools, Metal pixel renderer, and
  frame-pool suites: 92 passed, 0 failed, 0 skipped.
- Logging owner under Thread Sanitizer: 9 passed, 0 failed, 0 skipped, with no
  race diagnostics.
- Full iOS Simulator suite: 1320 passed, 0 failed, 0 skipped.
- Generic iOS device Release build: passed.
- Project syntax, stale logging-policy symbols, unsafe logging state, compiler
  warnings, and whitespace checks: clean.
- Result bundles:
  `/private/tmp/irplayer-logging-final-focused.xcresult`,
  `/private/tmp/irplayer-logging-snapshot-tsan.xcresult`, and
  `/private/tmp/irplayer-logging-final-full.xcresult`.
