# FFmpeg Dictionary And Metadata Ownership Design

## Summary

FFmpeg dictionaries currently cross the Swift boundary as a mutable
`AVDictionary` struct containing an `OpaquePointer?`. Callers create entries
through `IRFFDictionaryPolicy`, manually pair them with `av_dict_free`, and
read borrowed dictionaries through the misspelled
`IRFFFoundationBrigeOfAVDictionary` global function. Metadata parsing adds a
second forwarding-only `IRFFMetadataPolicy`.

Replace this with an explicit RAII `IRFFDictionary` owner for mutable option
dictionaries and direct value conversion for borrowed FFmpeg metadata. Make
`IRFFMetadata` an immutable value and consolidate its numeric parsing beside
the value.

## Problems

- Ownership is not visible in the `AVDictionary` wrapper; any copy duplicates
  the same mutable pointer without ownership semantics.
- Every mutable dictionary user must remember the exact `av_dict_free` pairing.
- Partial entry creation requires a manual cleanup branch.
- `IRFFDictionaryPolicy` combines owning mutation, borrowed traversal, C-string
  decoding, and test construction behind a generic policy name.
- Borrowed metadata traverses a misspelled global bridge before reaching its
  domain value.
- `IRFFMetadata` is a mutable reference type even though parsed metadata is a
  fixed value.
- Tests assert wrapper-to-policy equivalence instead of ownership, cleanup,
  parsing, and borrowed-view behavior.

## Goals

- Give every mutable FFmpeg dictionary exactly one non-copyable Swift owner.
- Free remaining dictionary entries automatically and make explicit close
  idempotent.
- Scope mutable raw-pointer access to fixed-result FFmpeg calls.
- Allow the owner to be passed directly to `avformat_open_input` while
  retaining ownership of unused options.
- Convert borrowed FFmpeg dictionaries directly into Swift values without
  claiming ownership.
- Decode only valid UTF-8 key/value pairs.
- Make parsed track metadata an immutable, equatable value.
- Keep checked integer parsing beside `IRFFMetadata`.
- Remove the typo bridge and both forwarding policies.

## Non-Goals

- Own dictionaries borrowed from `AVFormatContext` or `AVStream`.
- Change FFmpeg option keys or RTSP transport behavior.
- Change track discovery, ordering, or codec selection.
- Change metadata key names or numeric fallback values.
- Refactor format-context generation ownership again.

## Components

### `IRFFDictionary`

A final class owns one optional FFmpeg dictionary pointer.

- `init()` starts empty.
- `init?(entries:)` creates all entries or closes the partial dictionary and
  fails.
- `set(key:value:)` performs checked UTF-8 C-string mutation.
- `withMutableRawPointer` exposes `inout OpaquePointer?` only for one
  `Int32`-returning FFmpeg call.
- `values` returns a Swift value view of the current entries.
- `close()` is repeatable and calls `av_dict_free`.
- `deinit` calls `close()`.

The owner is a class so copying a Swift variable cannot create two owners of
the same raw pointer.

### Borrowed Dictionary Conversion

`IRFFDictionary.values(from:)` traverses a borrowed FFmpeg pointer without
freeing or mutating it. `string(fromCString:)` accepts only valid UTF-8.
Malformed pairs are skipped and an empty result becomes `nil`.

### `IRFFMetadata`

`IRFFMetadata` becomes an immutable `Equatable` struct with direct initializers
from a Swift dictionary or borrowed FFmpeg dictionary pointer. Checked Int64
conversion rejects booleans, fractional/non-finite numbers, overflow, and
malformed strings.

### Format Builder

The builder owns its option dictionary through `IRFFDictionary`. Any options
left after `avformat_open_input` are released automatically on every return
path. Format and stream metadata use the borrowed static conversion directly.

## Invariants

- A mutable FFmpeg dictionary pointer has exactly one `IRFFDictionary` owner.
- Closing or deinitializing the owner leaves its pointer nil.
- Partial entry construction cannot leak.
- A borrowed dictionary conversion never calls `av_dict_free`.
- Mutable raw-pointer access cannot escape through the operation's result.
- Invalid UTF-8 pairs are never inserted into Swift dictionaries.
- Parsed metadata fields cannot change after initialization.
- Invalid numeric metadata consistently resolves to zero.

## Testing

- Empty and all-or-nothing dictionary construction.
- Valid entry creation, replacement, and Swift value conversion.
- Explicit close idempotence and automatic release behavior diagnostics.
- Scoped raw-pointer borrowing and format-open option consumption.
- Missing and malformed borrowed C strings.
- Valid and malformed borrowed entry conversion.
- Immutable metadata equality and checked numeric parsing.
- Format-context open, failure, metadata, and teardown integration.

## Acceptance Criteria

- No copyable wrapper stores an owning FFmpeg dictionary pointer.
- Format options require no manual `av_dict_free`.
- `IRFFFoundationBrigeOfAVDictionary` is removed.
- `IRFFDictionaryPolicy.swift` and `IRFFMetadataPolicy.swift` are removed.
- Focused tests, Thread Sanitizer, format/decoder integration tests, the full
  simulator suite, and a generic iOS device build pass.
