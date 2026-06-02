# AGENTS.md — Tests

Unit test suite for the IRPlayer framework.

## Structure

All tests are in `IRPlayer-swiftTests/` — a single flat directory with one test file per component.

## Test Categories

### Player Tests
- `IRPlayerImpLazyPlayerTests.swift` — Player initialization and lazy setup
- `IRPlayerDecoderTests.swift` — Decoder configuration tests
- `IRPlayerNotificationTests.swift` — Notification dispatch tests
- `IRPlayerLifecyclePolicyTests.swift` — Lifecycle policy behavior
- `IRAVPlayerTests.swift` — AVPlayer backend tests
- `IRFFPlayerTests.swift` — FFmpeg player backend tests
- `IRModelPayloadTests.swift` — Model/payload serialization

### FFmpeg Decode Pipeline Tests
- `IRFFFormatContextTests.swift` — Format context open/read
- `IRFFAudioDecoderTests.swift` — Audio decoding
- `IRFFVideoDecoderTests.swift` — Video decoding
- `IRFFVideoToolBoxTests.swift` — Hardware decode via VideoToolBox
- `IRFFDecoderOperationTests.swift` — Decoder operation lifecycle
- `IRFFToolsTests.swift` — FFmpeg utility functions
- `IRFFTrackTests.swift` — Track metadata
- `IRFFMetadataTests.swift` — Stream metadata

### Frame Management Tests
- `IRFFAVYUVVideoFrameTests.swift` — YUV video frame
- `IRFFFramePoolTests.swift` — Frame pool reuse
- `IRFFFrameQueueTests.swift` — Frame queue thread safety
- `IRFFPacketQueueTests.swift` — Packet queue

### Rendering Pipeline Tests
- `IRGLProgram2DTests.swift` — 2D program
- `IRGLProgram2DFisheye2PanoTests.swift` — Fisheye-to-panorama program
- `IRGLProgram2DFisheye2PerspTests.swift` — Fisheye-to-perspective program
- `IRGLProgramDistortionTests.swift` — Distortion program
- `IRGLProgramMulti4PTests.swift` — Multi-4P program
- `IRGLProgramFactoryTests.swift` — Program factory
- `IRGLRenderModeBuildTests.swift` — Render mode construction
- `IRGLRenderModeFactoryTests.swift` — Render mode factory
- `IRGLRenderStrategyFactoryTests.swift` — Render strategy factory
- `IRGLViewSnapshotTests.swift` — Visual snapshot tests

### Transform & Controller Tests
- `IRGLTransformController2DTests.swift` — 2D transform
- `IRGLTransformController3DFisheyeTests.swift` — 3D fisheye transform
- `IRGLTransformControllerVRTests.swift` — VR transform
- `IRGLGestureControllerTests.swift` — Gesture input
- `IRePTZShiftControllerTests.swift` — Electronic PTZ

### Other Tests
- `IRGLScopeTests.swift` — Viewport scope bounds
- `IRGLShaderParamsTests.swift` — Shader parameters
- `IRMatrix4Tests.swift` — Matrix math
- `IRAudioManagerTests.swift` — Audio output

### Test Support
- `IRPlayerTestSupport.swift` — Shared test utilities, mocks, and helpers

## Running Tests

```bash
swift test                          # Run all tests
swift test --filter IRGLProgram2D   # Run specific test class
```

## Agent Notes

- Tests use the `IRPlayerSwift` module dependency.
- There are no integration tests requiring media files — tests use mocks/stubs.
- When adding new source files, add a corresponding test file following the naming convention: `<ClassName>Tests.swift`.
- Run relevant tests first, then broader tests if impact is cross-cutting.
