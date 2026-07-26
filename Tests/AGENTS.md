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
- `IRPlayerLoggerTests.swift` — Logging owner lifecycle, weak delegate,
  reentrancy, configuration coherence, and concurrency
- `IRPlaybackBackendEventRouterTests.swift` — Active-backend event admission
- `IRPlayerDecoderTests.swift` — Decoder configuration tests
- `IRPlayerNotificationTests.swift` — Notification dispatch tests
- `IRPlayerLifecycleDecisionTests.swift` — Lifecycle decision boundaries
- `IRPlayerLifecycleControllerTests.swift` — Stateful lifecycle transitions
- `IRAVPlayerSemanticsTests.swift` — AVPlayer state, time, seek, track,
  asset-load, and error-mapping semantics
- `IRAVPlayerTests.swift` — AVPlayer backend integration tests
- `IRAVPlayerPresentationLoopTests.swift` — VR display-link generation and
  lifecycle ownership
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
- `IRFFDecodeAdmissionTests.swift` — Shared capacity limits, occupancy, phase,
  and long-run recovery semantics
- `IRFFVideoDecoderTests.swift` — Video decoding, unified admission,
  generation fencing, and terminal-error cancellation
- `IRFFVideoInputTests.swift` — Pointer-free immutable custom values, typed
  one-shot completion, weak forwarding, and late-frame reclamation
- `IRFFVideoToolBoxTests.swift` — Hardware decode via VideoToolBox
- `IRFFVideoToolBoxSessionTests.swift` — VideoToolbox generation/callback ownership
- `IRFFDecoderOperationTests.swift` — Decoder operation lifecycle
- `IRFFDecoderSeekSemanticsTests.swift` — Decoder-owned seek bounds, resume,
  completion, and malformed arithmetic
- `IRFFDecoderAudioSemanticsTests.swift` — Decoder-owned audio admission,
  buffering, malformed clocks, and transitions
- `IRFFDecoderDisplaySemanticsTests.swift` — Decoder-owned display timing,
  ordering, idle, and overflow behavior
- `IRFFDecoderPacketSemanticsTests.swift` — Decoder-owned backpressure, EOF,
  and exact packet routing
- `IRFFDecoderCollaboratorSessionTests.swift` — Atomic weak collaborator
  generations, terminal revoke, delivery ordering, and concurrency
- `IRFFDictionaryTests.swift` — Owned options and borrowed dictionary values
- `IRFFToolsTests.swift` — FFmpeg utility functions
- `IRFFTrackTests.swift` — Track metadata
- `IRFFMetadataTests.swift` — Immutable stream metadata and numeric parsing

### Frame Management Tests
- `IRFFPacketTests.swift` — FFmpeg packet move/borrow/close ownership
- `IRFFAudioFrameTests.swift` — Managed PCM storage, reuse, and active bounds
- `IRFFAVYUVVideoFrameTests.swift` — YUV video frame
- `IRVideoFrameRGBTests.swift` — Atomic dimensions and immutable RGB24/BGRA32 generations
- `IRYUVImageConversionSessionTests.swift` — Scaler and managed RGB24 output ownership
- `IRFFFramePoolTests.swift` — Frame lifecycle, exact pool buckets, failure, close, and concurrency
- `IRFFFrameQueueTests.swift` — Immutable accounting, wakeup, ownership drain, close, and concurrency
- `IRFFPacketQueueTests.swift` — Owned packet queue and typed control items

### Rendering Pipeline Tests
- `IRGLProgram2DTests.swift` — 2D program
- `IRGLProgram2DFisheye2PanoTests.swift` — Fisheye-to-panorama program
- `IRGLProgram2DFisheye2PerspTests.swift` — Fisheye-to-perspective program
- `IRGLProgramDistortionTests.swift` — Distortion program
- `IRGLProgramMulti4PTests.swift` — Multi-4P program
- `IRGLProgramFactoryTests.swift` — Program factory
- `IRGLTransform2DSemanticsTests.swift` — 2D transform owner decisions,
  overflow rejection, and resize clamping
- `IRGLFisheyeTransformSemanticsTests.swift` — Fisheye transform owner
  decisions and constant-work angle normalization
- `IRGLFish2PanoPixelMapGenerationTests.swift` — Immutable managed lookup maps and scoped bytes
- `IRGLProjectionVRTests.swift` — Immutable shared VR mesh and concurrency
- `IRGLProjectionEquirectangularTests.swift` — Mesh validation, geometry generations, snapshots, and concurrency
- `IRMetalCommandResourcesTests.swift` — GPU-completion resource lifetime and command caching
- `IRMetalDistortionTargetSessionTests.swift` — Distortion target generation, failure, close, and concurrency ownership
- `IRMetalFrameTextureGenerationTests.swift` — Complete Core Video and managed texture generations
- `IRMetalMeshStorageTests.swift` — Checked shared mesh storage and index arithmetic
- `IRMetalRendererResourcesTests.swift` — Complete renderer bootstrap and typed resource failures
- `IRGLRenderModeBuildTests.swift` — Render mode construction
- `IRGLRenderModeFactoryTests.swift` — Render mode factory
- `IRGLRenderStrategyFactoryTests.swift` — Render strategy factory
- `IRGLViewSnapshotTests.swift` — Visual snapshot tests

### Transform & Controller Tests
- `IRGLTransformController2DTests.swift` — 2D transform
- `IRGLTransformController3DFisheyeTests.swift` — 3D fisheye transform
- `IRGLTransformControllerVRTests.swift` — VR transform
- `IRBounceControllerTests.swift` — Bounce geometry and animation semantics
- `IRGestureControllerTests.swift` — Base gesture semantics and callbacks
- `IRGLGestureControllerTests.swift` — Gesture input
- `IRDisplayLinkDriverTests.swift` — Shared display-link lifecycle owner
- `IRSmoothScrollSessionTests.swift` — Locked animation state and calculations
- `IRSmoothScrollControllerTests.swift` — UI facade, failure, and stale ticks
- `IRePTZShiftControllerTests.swift` — Electronic PTZ
- `IRSensorMotionDriverTests.swift` — Immutable Core Motion value boundary
- `IRSensorMotionSessionTests.swift` — Generation-fenced motion state and math
- `IRSensorTests.swift` — Sensor lifecycle, delivery, and concurrency

### Other Tests
- `IRPlaybackTimeRangeTests.swift` — Validated shared playback-duration bounds
- `IRGLScopeTests.swift` — Viewport scope bounds
- `IRGLShaderParamsTests.swift` — Shader parameters
- `IRMatrix4Tests.swift` — Matrix math
- `IRAudioManagerTests.swift` — Audio output
- `IRPhotoSaverTests.swift` — Photo-library transaction stages, coalescing,
  closure, duplicate callback rejection, and concurrency

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
- Test owner semantics directly; do not add wrapper-versus-policy mirror tests.
- Custom-decode tests must cover routing before packet copying, every typed
  outcome, exactly-once completion, bounded deferred reservations, EOF wait,
  generation invalidation, terminal cancellation, and late-frame reclamation.
- Run relevant tests first, then broader tests if impact is cross-cutting.
