# AGENTS.md — Tools

Utility helpers used across the framework.

## Files

| File                          | Purpose                                      |
|-------------------------------|----------------------------------------------|
| `IRFFMpegErrorUtil.swift`     | Converts FFmpeg error codes to Swift errors  |
| `IRYUVImageConversionSession.swift` | Owned FFmpeg scaler and managed RGB24 output |
| `IRYUVTools.swift`            | Checked YUV geometry, row copy, and image API |
| `IRPhotoSaver.swift`          | Photo-save values and compatibility facade   |
| `IRPhotoLibrarySession.swift` | Owned photo-library transactions and Photos driver |

## Agent Notes

- `IRFFMpegErrorUtil.swift` bridges the Objective-C `IRFFMpegErrorUtil` from the `IRPlayerObjc` target.
- YUV snapshot conversion must keep `SwsContext` lifetime inside
  `IRYUVImageConversionSession` and output bytes in Swift-managed storage.
- Keep source/output pointers scoped to `withConvertedRGB`; do not reintroduce
  `av_image_alloc` or a free-function-owned scaler.
- `IRYUVTools` is used by the rendering pipeline for pixel format conversions
  and retains its established helper signatures.
- Photo saves must flow through `IRPhotoLibrarySession`. Publish each request
  stage before calling the driver, reject duplicate or stale callbacks, and
  invoke driver and client closures only while the session lock is released.
- Keep Photos framework objects inside `IRSystemPhotoLibraryDriver`; the
  session boundary should exchange only Swift values and `UIImage`.
- Tests: `IRFFToolsTests.swift`, `IRYUVImageConversionSessionTests.swift`, and
  `IRPhotoSaverTests.swift`.
