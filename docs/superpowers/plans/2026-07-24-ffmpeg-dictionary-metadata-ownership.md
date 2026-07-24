# FFmpeg Dictionary And Metadata Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-ffmpeg-dictionary-metadata-ownership-design.md`.

## Phase 1: Dictionary Owner

- [x] Replace the copyable raw-pointer wrapper with `IRFFDictionary`.
- [x] Add all-or-nothing entry construction and checked mutation.
- [x] Add fixed-result scoped raw-pointer access.
- [x] Add idempotent close and automatic cleanup.
- [x] Add borrowed dictionary and C-string value conversion.

## Phase 2: Metadata Value

- [x] Convert `IRFFMetadata` to an immutable equatable struct.
- [x] Move checked Int64 parsing into the metadata domain.
- [x] Initialize metadata directly from borrowed FFmpeg dictionaries.
- [x] Preserve key names and invalid-value defaults.

## Phase 3: Integration And Consolidation

- [x] Use the dictionary owner for format open options.
- [x] Convert format and stream metadata through the borrowed view.
- [x] Remove manual option dictionary cleanup.
- [x] Remove `IRFFFoundationBrigeOfAVDictionary`.
- [x] Remove `IRFFDictionaryPolicy.swift`.
- [x] Remove `IRFFMetadataPolicy.swift`.

## Phase 4: Tests

- [x] Replace wrapper-equivalence tests with owner/value assertions.
- [x] Add construction, replacement, scoped borrow, and close coverage.
- [x] Add valid and malformed borrowed entry coverage.
- [x] Add immutable metadata and numeric boundary coverage.
- [x] Preserve format-context open/failure/teardown coverage.

## Phase 5: Verification

- [x] Run focused dictionary/metadata/tools/track/format tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run format-resource, decoder-session, and FFPlayer integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata, stale-symbol, and whitespace validation.
- [x] Update FFmpeg guidance and the 2.0 completion audit.
- [x] Create a focused commit.

## Verification Record

Completed on 2026-07-24:

- Dictionary, metadata, tools, track, and format-context focused suites:
  64 passed, 0 failed.
- The same 64 tests under Thread Sanitizer: passed with no race diagnostics.
- Format-resource, decoder, decoder-session, and all FFPlayer runtime-owner
  integration suites: 218 passed, 0 failed.
- Full iOS Simulator suite: 1141 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package resolution, package dump/description, Xcode project listing,
  project property-list validation, stale-symbol search, and
  `git diff --check`: passed.
