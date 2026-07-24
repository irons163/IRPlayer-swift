# AGENTS.md — Tests

Unit test suite for the IRPlayer framework.

## Structure

All tests are in `IRPlayer-swiftTests/` — a single flat directory with one test file per component.

## Test Categories

### Player Tests
- `IRPlayerImpLazyPlayerTests.swift` — Player initialization and lazy setup
- `IRPlayerFacadeRuntimeTests.swift` — Facade owner integration and transactions
- `IRPlayerFacadeStateTests.swift` — Settings and media-session state ownership
- `IRPlayerEnvironmentSessionTests.swift` — App/audio lifecycle ownership
- `IRPlayerPresentationSessionTests.swift` — Display and interaction ownership
- `IRPlaybackBackendEventRouterTests.swift` — Active-backend event admission
- `IRPlayerDecoderTests.swift` — Decoder configuration tests
- `IRPlayerNotificationTests.swift` — Notification dispatch tests
- `IRPlayerLifecycleDecisionTests.swift` — Lifecycle decision boundaries
- `IRPlayerLifecycleControllerTests.swift` — Stateful lifecycle transitions
- `IRAVPlayerTests.swift` — AVPlayer backend tests
- `IRFFPlayerTests.swift` — FFmpeg player backend tests
- `IRModelPayloadTests.swift` — Model/payload serialization

### FFmpeg Decode Pipeline Tests
- `IRFFFormatContextTests.swift` — Format context open/read
- `IRFFFormatContextResourcesTests.swift` — FFmpeg generation/callback ownership
- `IRFFAudioDecoderTests.swift` — Audio decoding
- `IRFFAudioResampleSessionTests.swift` — Resampler/context/scratch ownership
- `IRFFDecodeFrameTests.swift` — Shared AVFrame scratch ownership
- `IRFFAudioFrameTests.swift` — Managed decoded-audio storage and checked copy
- `IRFFAudioRendererTests.swift` — Real-time decoded-audio consumption
- `IRFFVideoDecoderTests.swift` — Video decoding
- `IRFFVideoToolBoxTests.swift` — Hardware decode via VideoToolBox
- `IRFFVideoToolBoxSessionTests.swift` — VideoToolbox generation/callback ownership
- `IRFFDecoderOperationTests.swift` — Decoder operation lifecycle
- `IRFFDictionaryTests.swift` — Owned options and borrowed dictionary values
- `IRFFToolsTests.swift` — FFmpeg utility functions
- `IRFFTrackTests.swift` — Track metadata
- `IRFFMetadataTests.swift` — Immutable stream metadata and numeric parsing

### Frame Management Tests
- `IRFFPacketTests.swift` — FFmpeg packet move/borrow/close ownership
- `IRFFAudioFrameTests.swift` — Managed PCM storage, reuse, and active bounds
- `IRFFAVYUVVideoFrameTests.swift` — YUV video frame
- `IRYUVImageConversionSessionTests.swift` — Scaler and managed RGB24 output ownership
- `IRFFFramePoolTests.swift` — Frame pool reuse
- `IRFFFrameQueueTests.swift` — Frame queue thread safety
- `IRFFPacketQueueTests.swift` — Owned packet queue and typed control items

### Rendering Pipeline Tests
- `IRGLProgram2DTests.swift` — 2D program
- `IRGLProgram2DFisheye2PanoTests.swift` — Fisheye-to-panorama program
- `IRGLProgram2DFisheye2PerspTests.swift` — Fisheye-to-perspective program
- `IRGLProgramDistortionTests.swift` — Distortion program
- `IRGLProgramMulti4PTests.swift` — Multi-4P program
- `IRGLProgramFactoryTests.swift` — Program factory
- `IRGLFish2PanoPixelMapGenerationTests.swift` — Immutable managed lookup maps and scoped bytes
- `IRGLProjectionVRTests.swift` — Immutable shared VR mesh and concurrency
- `IRGLProjectionEquirectangularTests.swift` — Mesh validation, geometry generations, snapshots, and concurrency
- `IRMetalCommandResourcesTests.swift` — GPU-completion resource lifetime and command caching
- `IRMetalFrameTextureGenerationTests.swift` — Complete Core Video and managed texture generations
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
- `IRSensorMotionDriverTests.swift` — Immutable Core Motion value boundary
- `IRSensorMotionSessionTests.swift` — Generation-fenced motion state and math
- `IRSensorTests.swift` — Sensor lifecycle, delivery, and concurrency

### Other Tests
- `IRGLScopeTests.swift` — Viewport scope bounds
- `IRGLShaderParamsTests.swift` — Shader parameters
- `IRMatrix4Tests.swift` — Matrix math
- `IRAudioManagerTests.swift` — Audio output

### Test Support
- `IRPlayerTestSupport.swift` — Shared test utilities, mocks, and helpers

## Running Tests

```bash
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift \
  -destination 'platform=iOS Simulator,id=<simulator-udid>'
```

## Agent Notes

- Tests use the `IRPlayer_swift` module dependency.
- Some decoder integration tests use generated or bundled media fixtures.
- When adding new source files, add a corresponding test file following the naming convention: `<ClassName>Tests.swift`.
- Run relevant tests first, then broader tests if impact is cross-cutting.
