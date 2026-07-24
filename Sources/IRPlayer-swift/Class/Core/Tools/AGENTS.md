# AGENTS.md — Tools

Utility helpers used across the framework.

## Files

| File                          | Purpose                                      |
|-------------------------------|----------------------------------------------|
| `IRFFMpegErrorUtil.swift`     | Converts FFmpeg error codes to Swift errors  |
| `IRYUVImageConversionSession.swift` | Owned FFmpeg scaler and managed RGB24 output |
| `IRYUVTools.swift`            | Checked YUV geometry, row copy, and image API |
| `IRPhotoSaver.swift`          | Save video frames as photos to the library   |

## Agent Notes

- `IRFFMpegErrorUtil.swift` bridges the Objective-C `IRFFMpegErrorUtil` from the `IRPlayerObjc` target.
- YUV snapshot conversion must keep `SwsContext` lifetime inside
  `IRYUVImageConversionSession` and output bytes in Swift-managed storage.
- Keep source/output pointers scoped to `withConvertedRGB`; do not reintroduce
  `av_image_alloc` or a free-function-owned scaler.
- `IRYUVTools` is used by the rendering pipeline for pixel format conversions
  and retains its established helper signatures.
- Tests: `IRFFToolsTests.swift`.
