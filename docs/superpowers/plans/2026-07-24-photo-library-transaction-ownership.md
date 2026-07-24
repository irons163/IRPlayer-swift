# Photo Library Transaction Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-photo-library-transaction-ownership-design.md`.

## Phase 1: Baseline and Values

- [x] Audit photo save call sites, Photos callbacks, policy wrappers, and tests.
- [x] Record the focused photo-saver baseline.
- [x] Move failure, outcome, destination, and normalization values into
  `IRPhotoSaver`.
- [x] Define the value-only photo-library driver boundary.

## Phase 2: Transaction Owner

- [x] Add explicit session and per-request phases.
- [x] Publish request stages before every external operation.
- [x] Add exactly-once completion and stale/duplicate callback rejection.
- [x] Coalesce same-name album creation.
- [x] Add terminal idempotent close and silent deinitialization.
- [x] Add complete diagnostics.

## Phase 3: System Integration

- [x] Isolate every Photos object and change request in the system driver.
- [x] Route the compatibility facade through one system session.
- [x] Preserve existing snapshot save call sites.
- [x] Remove `IRPhotoSaverPolicy.swift` and its project entries.
- [x] Update local architecture guidance.

## Phase 4: Tests

- [x] Cover value normalization and default diagnostics.
- [x] Cover permission, library save, existing album, and album creation.
- [x] Cover every failure and missing-identifier path.
- [x] Cover synchronous, reentrant, duplicate, stale, and out-of-order
  callbacks.
- [x] Cover coalesced concurrent album requests.
- [x] Cover close, post-close rejection, late callbacks, and deinitialization.
- [x] Cover concurrent request/completion/close behavior.
- [x] Preserve snapshot-session integration coverage.

## Phase 5: Verification

- [x] Run focused saver and snapshot-session suites.
- [x] Run the transaction boundary under Thread Sanitizer.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run project, stale-symbol, warning, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Photo-saver tests: 8 passed, 0 failed, 0 skipped.

## Focused Verification

Recorded on 2026-07-24 after implementation:

- Photo-saver and snapshot-session tests: 20 passed, 0 failed, 0 skipped.
- Result bundle:
  `/private/tmp/irplayer-photo-session-focused-final.xcresult`.
- The same 20 tests passed under Thread Sanitizer with no race diagnostics.
  Result bundle: `/private/tmp/irplayer-photo-session-tsan-final.xcresult`.
- Full iOS Simulator suite: 1,313 passed, 0 failed, 0 skipped.
  Result bundle: `/private/tmp/irplayer-photo-session-full-final.xcresult`.
- Generic iOS device Release build: passed.
