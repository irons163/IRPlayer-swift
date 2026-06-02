# AGENTS.md — Tools

Utility helpers used across the framework.

## Files

| File                          | Purpose                                      |
|-------------------------------|----------------------------------------------|
| `IRFFMpegErrorUtil.swift`     | Converts FFmpeg error codes to Swift errors  |
| `IRYUVTools.swift`            | YUV pixel format conversion utilities        |
| `IRPhotoSaver.swift`          | Save video frames as photos to the library   |

## Agent Notes

- `IRFFMpegErrorUtil.swift` bridges the Objective-C `IRFFMpegErrorUtil` from the `IRPlayerObjc` target.
- `IRYUVTools` is used by the rendering pipeline for pixel format conversions.
- Tests: `IRFFToolsTests.swift`.
