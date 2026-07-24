# AGENTS.md — FFmpeg

FFmpeg decode pipeline — format context, decoders, frames, and utilities.

## Files

| File                         | Purpose                                              |
|------------------------------|------------------------------------------------------|
| `IRFFFormatContext.swift`    | FFmpeg format context wrapper (open, read, seek)     |
| `IRFFDecoder.swift`          | Decoder orchestration (coordinates audio + video)    |
| `IRFFAudioDecoder.swift`     | Audio packet → audio frame decoding                  |
| `IRFFVideoDecoder.swift`     | Video packet → video frame decoding                  |
| `IRFFVideoToolBox.swift`     | Hardware-accelerated decoding via VideoToolBox        |
| `IRFFVideoToolBoxSession.swift` | VideoToolbox generations, leases, and callbacks    |
| `IRFFVideoToolBoxH264.swift` | AVCC, NAL, and Core Media payload construction        |
| `IRFFVideoInput.swift`       | Custom video input for direct frame injection        |
| `IRFFTrack.swift`            | Audio/video track metadata                           |
| `IRFFMetadata.swift`         | Stream metadata extraction                           |
| `IRFFTools.swift`            | FFmpeg utility functions                             |

## Subdirectory

- `Frame/` — Frame data models and queue management.

## Agent Notes

- `IRFFFormatContext` opens media and provides packet streams.
- `IRFFDecoder` coordinates the decode loop across audio and video.
- `IRFFVideoToolBox` wraps Apple's VideoToolBox for hardware H.264/H.265 decoding.
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
- Tests: `IRFFFormatContextTests.swift`, `IRFFAudioDecoderTests.swift`,
  `IRFFVideoDecoderTests.swift`, `IRFFVideoToolBoxTests.swift`,
  `IRFFVideoToolBoxSessionTests.swift`, `IRFFToolsTests.swift`,
  `IRFFTrackTests.swift`, `IRFFMetadataTests.swift`, and
  `IRFFDecoderOperationTests.swift`.
