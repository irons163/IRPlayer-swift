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
- `IRFFVideoInput` allows bypassing the decode pipeline entirely for custom frame sources.
- Tests: `IRFFFormatContextTests.swift`, `IRFFAudioDecoderTests.swift`, `IRFFVideoDecoderTests.swift`, `IRFFVideoToolBoxTests.swift`, `IRFFToolsTests.swift`, `IRFFTrackTests.swift`, `IRFFMetadataTests.swift`, `IRFFDecoderOperationTests.swift`.
