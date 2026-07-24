# AGENTS.md — FFmpeg

FFmpeg decode pipeline — format context, decoders, frames, and utilities.

## Files

| File                         | Purpose                                              |
|------------------------------|------------------------------------------------------|
| `IRFFFormatContext.swift`    | Serialized input-generation lifecycle facade         |
| `IRFFFormatContextBuilder.swift` | FFmpeg input/codec generation construction       |
| `IRFFFormatContextResources.swift` | C-resource and interrupt-callback ownership     |
| `IRFFFormatContextSemantics.swift` | Pure timing, track, and selection semantics      |
| `IRFFDecoder.swift`          | Decoder orchestration (coordinates audio + video)    |
| `IRFFAudioDecoder.swift`     | Audio packet → audio frame decoding                  |
| `IRFFVideoDecoder.swift`     | Video packet → video frame decoding                  |
| `IRFFVideoToolBox.swift`     | Hardware-accelerated decoding via VideoToolBox        |
| `IRFFVideoToolBoxSession.swift` | VideoToolbox generations, leases, and callbacks    |
| `IRFFVideoToolBoxH264.swift` | AVCC, NAL, and Core Media payload construction        |
| `IRFFVideoInput.swift`       | Custom video input for direct frame injection        |
| `IRFFTrack.swift`            | Audio/video track metadata                           |
| `IRFFDictionary.swift`       | Owned options and borrowed metadata conversion       |
| `IRFFMetadata.swift`         | Immutable parsed stream metadata                     |
| `IRFFTools.swift`            | FFmpeg utility functions                             |

## Subdirectory

- `Frame/` — Frame data models and queue management.

## Agent Notes

- `IRFFFormatContext` opens media and provides packet streams.
- Publish one complete format/codec generation only after at least one usable
  audio or video track opens. Do not expose partially initialized FFmpeg
  pointers.
- Keep format setup, packet reads, seeks, track replacement, and destruction
  serialized through the format-context operation gate.
- `destroy()` requests interruption before waiting for the operation gate,
  then transitions terminally to closed.
- FFmpeg interrupt callbacks use a separately retained
  `IRFFFormatContextInterruptState`; never point `opaque` at an unretained
  facade.
- Every context returned by `avcodec_alloc_context3` must be destroyed with
  `avcodec_free_context`. Do not replace it with `avcodec_close`, which leaves
  the `AVCodecContext` allocation alive.
- Close the input context before releasing its retained callback reference.
- Mutable FFmpeg option dictionaries must have one `IRFFDictionary` owner;
  pass its pointer only through the fixed-result scoped borrow.
- Format and stream metadata dictionaries are borrowed. Convert them to Swift
  values without freeing or retaining their FFmpeg pointers.
- `IRFFDecoder` coordinates the decode loop across audio and video.
- `IRFFVideoToolBox` wraps Apple's VideoToolBox for hardware H.264 decoding.
- Keep VideoToolbox setup, decode, reset, and close serialized through the
  facade operation gate.
- Publish a complete `VTDecompressionSession` generation through
  `IRFFVideoToolBoxSession`; never store a separate setup token or partially
  initialized resource fields.
- Reset is repeatable, close is terminal, and stale setup tickets must not
  publish after either transition.
- Active generation leases must drain before waiting for frames, invalidating
  the session, and releasing its callback reference.
- The VideoToolbox callback context is retained per session generation. Do not
  point callbacks at an unretained facade or release the context before session
  invalidation.
- Decode currently uses empty Videotoolbox flags and depends on the documented
  synchronous callback-before-return contract. If async or temporal flags are
  introduced, redesign result correlation before enabling them.
- `IRFFVideoInput` allows bypassing the decode pipeline entirely for custom frame sources.
- Tests: `IRFFFormatContextTests.swift`,
  `IRFFFormatContextResourcesTests.swift`, `IRFFAudioDecoderTests.swift`,
  `IRFFVideoDecoderTests.swift`, `IRFFVideoToolBoxTests.swift`,
  `IRFFVideoToolBoxSessionTests.swift`, `IRFFToolsTests.swift`,
  `IRFFDictionaryTests.swift`, `IRFFTrackTests.swift`,
  `IRFFMetadataTests.swift`, and
  `IRFFDecoderOperationTests.swift`.
