# AVPlayer Domain Semantics Consolidation Design

## Summary

The AVPlayer backend already has explicit lifecycle, presentation-loop, and
resource-session owners, but its pure behavior still crosses an unnecessary
second abstraction layer:

- `IRAVPlayer` exposes static playback and time helpers that forward one-to-one
  into `IRAVPlayerPlaybackPolicy` and `IRAVPlayerTimePolicy`;
- `IRAVPlayerTracks` forwards track parsing and selection into
  `IRAVPlayerTrackPolicy`;
- `IRAVPlayerLifecycle` forwards error construction into
  `IRAVPlayerErrorPolicy`; and
- tests call both layers and compare them for equality.

This is not separation of concerns. It creates two internal APIs for every
decision, spreads one backend across four extra files, and lets facade/policy
implementations drift while tests prove only that both currently agree.

Move each behavior into its owning AVPlayer domain extension, remove the four
policy types, and split pure semantics tests out of the 1,300-line
`IRAVPlayerTests.swift` integration suite.

## Problems

- Four policy files are referenced only by their matching AVPlayer facade and
  tests.
- Wrapper-comparison tests duplicate implementation structure instead of
  proving externally relevant behavior.
- Playback state tables are asserted piecemeal rather than as complete
  state-space mappings.
- Track, time, and error-value tests are buried among AVFoundation integration
  and lifecycle tests.
- Error snapshots and builders live outside the lifecycle domain that consumes
  them.
- The project file and local architecture guidance preserve obsolete layers.

## Goals

- Make `IRAVPlayer` the only internal API for AVPlayer playback and time
  semantics.
- Keep track parsing/default selection beside track setup and selection.
- Keep error-log snapshots and `IRError` mapping beside failure lifecycle.
- Remove all one-to-one AVPlayer policy forwarding.
- Preserve the existing public playback API and runtime behavior.
- Replace structural wrapper comparisons with complete behavior tables.
- Split pure deterministic tests into `IRAVPlayerSemanticsTests.swift`.
- Add edge coverage for every `IRPlayerState`, malformed track identifiers,
  invalid time values, error precedence, and empty extended logs.
- Reduce the remaining first-party policy inventory from 33 to 29.

## Non-Goals

- Change AVPlayer resource ownership, observation tokens, presentation-loop
  lifecycle, or seek generation ownership.
- Change the public `IRPlayerImp` API.
- Change ready/buffering/play/pause decisions.
- Change track-selection fallback behavior.
- Change `IRError` or `IRErrorEvent` public model shapes.
- Change AVFoundation deprecated API usage in this slice.

## Domain Placement

### Playback and Time

`IRAVPlayer.swift` already exposes the semantic entry points used by commands,
periodic progress, and tests. Replace their forwarding bodies with the
decisions themselves:

- item-status decision;
- play and pause transition;
- delayed retry and active-state classification;
- seek-time validation;
- finite `CMTime` conversion; and
- playable-range clamping.

These functions remain pure and internal.

### Tracks

`IRAVPlayerTracks.swift` owns media-selection group traversal, track model
construction, selection, and cleanup. It will also directly own:

- fallback display names;
- strict property-list track-ID parsing; and
- deterministic default-track fallback.

No second track-policy type remains.

### Errors

`IRAVPlayerLifecycle.swift` owns playback failure detection and delivery. It
will directly own an immutable `ErrorLogEventSnapshot` plus mapping from
AVFoundation errors/log events into `IRError` and `IRErrorEvent`.

Player-item errors retain precedence over player errors. Extended log data and
events apply only when an item error exists. Missing errors retain the existing
fallback domain and code.

### Tests

`IRAVPlayerSemanticsTests.swift` becomes the focused suite for pure playback,
time, track, asset-decision, redirect, and error semantics.

`IRAVPlayerTests.swift` remains responsible for backend integration,
AVFoundation resource behavior, commands, callbacks, replacement, tracks, and
presentation. Pure tests are moved rather than duplicated, then strengthened
with table-driven cases.

## Invariants

- Every AVPlayer semantic decision has one implementation and one internal
  entry point.
- No test compares a facade with a hidden forwarding type.
- Every `IRPlayerState` is represented in playback transition tables.
- Track IDs accept only exactly representable integer numbers, never booleans,
  fractions, strings, or overflow.
- Non-finite or invalid times never escape as progress or seek values.
- Item errors win over player errors and are the only source of extended log
  payloads/events.
- Integration code continues calling the same `IRAVPlayer` static functions.

## Testing

- Table-test item status across all current player states.
- Table-test play, pause, retry, and active classifications across all states.
- Test finite, zero, negative, non-finite, invalid, and overflowing time input.
- Test track display names, property-list type rejection, exact integers, and
  default fallback.
- Test item/player/fallback error precedence.
- Test complete event copying and empty/non-empty extended logs.
- Preserve AVPlayer session, presentation-loop, generated-media, command,
  replacement, and teardown integration tests.

## Acceptance Criteria

- `IRAVPlayerErrorPolicy.swift`, `IRAVPlayerPlaybackPolicy.swift`,
  `IRAVPlayerTimePolicy.swift`, and `IRAVPlayerTrackPolicy.swift` are removed
  from disk and the Xcode project.
- No first-party source or test references the four removed symbols.
- Pure AVPlayer semantics have direct behavioral tests in a focused file.
- Changed sources emit no warnings.
- Focused tests, Thread Sanitizer coverage, the full simulator suite, and a
  generic iOS device Release build pass.
