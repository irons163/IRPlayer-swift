# IRPlayer SDK guide

This guide describes the Swift-first API on the current development line of
IRPlayer-swift. It is written against the source in this repository. The
published `2.0` tag predates the current API redesign, so applications should
pin the exact release or candidate ref they have reviewed.

## Package surface

The package declares iOS 15 as its minimum deployment target. Build the current
source with Xcode 26 or later: the VideoToolbox integration uses
`VTDecodeInfoFlags.frameInterrupted`, which is unavailable in the older Xcode
16.4 SDK. Add the package repository in Xcode, select the `IRPlayer` library
product, and import `IRPlayerSwift` from Swift code:

```swift
dependencies: [
    .package(
        url: "https://github.com/irons163/IRPlayer-swift.git",
        branch: "codex/2.0-refactor-stack"
    )
]
```

The package includes the FFmpeg wrapper and prebuilt iOS FFmpeg XCFrameworks.
The Swift package does not expose a macOS playback target. The shared display
view hosts an AVPlayerLayer for normal AVFoundation playback and Metal
renderers for FFmpeg and immersive/custom modes.

The branch in the snippet is the current candidate line. Pin the exact
reviewed revision or release requirement for production after the next version
is selected.

The source of truth for symbol signatures is the
[IRPlayer Swift DocC catalog](../../Sources/IRPlayer-swift/IRPlayer_swift.docc/IRPlayer_swift.md).
The [demo app](../../SPMDemo/) contains an iOS integration with local media,
the legacy notification API, and the eight rendering acceptance scenarios.

## The player facade

`IRPlayer` is a public typealias for `IRPlayerImp`. Construct it with the
Swift-first configuration initializer or use `IRPlayerImp.player()` when
maintaining an older integration:

```swift
let player = IRPlayer(configuration: IRPlayerConfiguration(
    autoplay: false,
    isLiveStream: false,
    playableBufferInterval: 2,
    volume: 1,
    gravityMode: .resizeAspect,
    displayMode: .normal,
    backgroundPolicy: .pauseAndResume
))
```

The configuration has these defaults:

| Property | Default | Meaning |
| --- | --- | --- |
| `decoder` | `IRPlayerDecoder.defaultDecoder()` | URL based backend rules. |
| `autoplay` | `false` | Start after a successful load. |
| `isLiveStream` | `false` | Use live stream timing behavior. |
| `playableBufferInterval` | `2` | Desired buffered interval in seconds. |
| `volume` | `1` | Audio volume, normalized to `0...1`. |
| `gravityMode` | `.resizeAspect` | How the view fits its content. |
| `displayMode` | `.normal` | VR presentation mode; `.box` enables VR Box. |
| `backgroundPolicy` | `.pauseAndResume` | Pause while backgrounded and resume when active. |

`playableBufferInterval` rejects negative values by normalizing them to zero;
non-finite values use two seconds. `volume` clamps finite values to `0...1`
and uses one for non-finite input. The same normalization applies when these
properties are changed directly on the player.

The player creates `view` during initialization. Add that view to your view
hierarchy and update its frame from your container's layout lifecycle. The view
is a UIKit display surface; its active renderer can be an AVPlayerLayer or a
Metal renderer depending on the backend and presentation mode.

## Load, replace, and stop

`IRMediaSource` groups all input decisions for one load:

```swift
let source = IRMediaSource(
    url: mediaURL,
    headers: [:],
    videoType: .normal,
    videoInput: nil,
    backendPreference: .automatic
)

player.load(source, autoplay: true)
```

`url` is optional at the value level so invalid input can be represented and
reported. A call to `load(IRMediaSource(url: nil))` resets the current session
and emits a typed load failure; call `stop()` when the intention is to clear
playback without reporting invalid input.

When its backend activates, a load replaces the current backend and source.
Replacement invalidates old decode and presentation work, including pending
seek completions and deferred custom decode completions; source validation or
backend-construction errors reset the session and report a load error. Cached
backend objects are owned by the player coordinator and are not application
API.

Use these operations for the normal lifecycle:

```swift
player.play()
player.pause()
player.seekToTime(time: 30) { didComplete in
    print("seek completed:", didComplete)
}
player.stop()
```

The seek completion receives `false` when the player has no active decoder, the
request is invalid, or replacement/stop invalidates the request. The public
snapshots `state`, `presentationSize`, `progress`, `duration`, `playableTime`,
`isSeeking`, and `activeBackend` can be read without reaching into a backend.

When the player is no longer needed, release it or call `stop()` as part of the
owning screen's teardown. The player closes its runtime owners during
deinitialization.

## Backend rules

`IRPlaybackBackendPreference.automatic` is the normal choice. The source is
resolved before a backend is constructed:

| Source condition | Automatic result |
| --- | --- |
| Non-empty headers | FFmpeg. |
| `videoInput` is present | FFmpeg. |
| `videoType` is `.fisheye`, `.pano`, or `.custom` | FFmpeg. |
| `.mp4` URL with `.normal` or `.vr` | The decoder's `mpeg4Format` rule; default AVFoundation. |
| `.m3u8` URL with `.normal` or `.vr` | AVFoundation by default. |
| RTSP, RTMP, or FLV URL | FFmpeg by default. |
| Unknown URL | The decoder's unknown-format rule; default FFmpeg. |

Format detection is case-insensitive and uses the URL path/string: `.mp4`,
`.m3u8`, `.flv`, and the `rtmp:`/`rtsp:` schemes are recognized. Source-level
preference wins where the configuration is compatible:

```swift
player.load(IRMediaSource(
    url: streamURL,
    backendPreference: .ffmpeg
))
```

`IRPlayerDecoder.defaultDecoder()` provides the standard rules.
`IRPlayerDecoder.FFmpegDecoder()` and `IRPlayerDecoder.AVPlayerDecoder()`
provide all-FFmpeg and all-AVFoundation rule sets. An all-AVFoundation rule
does not make RTSP, RTMP, FLV, or custom input supported; the underlying
backend still needs to open the source. Set
`ffmpegHardwareDecoderEnable = false` to request software FFmpeg decoding.
The public `mpeg4Format` property can override the MP4 rule.

Custom headers and AVFoundation are deliberately incompatible when the source
explicitly requests `.avFoundation`. A public AVFoundation resource loader
cannot guarantee headers on every HLS playlist and segment request. Automatic
resolution therefore chooses FFmpeg whenever headers are present.

## States, events, and observation lifetime

Observe events through `observeEvents(_:)`:

```swift
private var observation: IRPlayerObservation?

observation = player.observeEvents { event in
    switch event {
    case let .stateChanged(previous, current):
        print(previous, "->", current)
    case let .progress(time):
        print(time.current, time.total, time.fraction)
    case let .playable(time):
        print("playable:", time.current)
    case let .failure(error):
        print(error.error.domain, error.error.code)
    }
}
```

`IRPlayerEvent` contains four cases:

- `.stateChanged(previous:current:)` reports `IRPlayerState` transitions.
- `.progress(IRPlayerTimeSnapshot)` reports playback time.
- `.playable(IRPlayerTimeSnapshot)` reports the buffered playable time.
- `.failure(IRError)` reports a terminal backend or load error.

`IRPlayerTimeSnapshot.fraction` is finite and normalized to `0...1`.
`current` and `total` are finite non-negative values. `total` may be zero for
live or not-yet-known duration. The event emitter delivers handlers on the
main thread. Treat each callback as a snapshot and do not infer ordering across
concurrent backend work.

Retain the observation token for as long as the handler is needed. Calling
`cancel()` is idempotent; releasing the token cancels it as well. The token does
not keep the player alive.

## Presentation and interaction

The source's `videoType` selects the default mode and interaction owner:

| `videoType` | Default rendering | Interaction |
| --- | --- | --- |
| `.normal` | Flat 2D | Gestures. |
| `.vr` | Stereoscopic VR | Gestures. |
| `.vr` plus `displayMode = .box` | VR Box distortion | Device motion. |
| `.fisheye` | 3D fisheye | Gestures. |
| `.pano` | Fisheye-to-panorama | Gestures. |
| `.custom` | Existing `renderModes` | Gestures. |

`displayMode` changes the VR presentation setup. `viewGravityMode` maps to
`.resize`, `.resizeAspect`, or `.resizeAspectFill`. Call
`updateGraphicsViewFrame(frame:)` after the containing view changes size.

For a custom player UI, call `setupPlayerView(_:)` with a `UIView` on the main
thread. The supplied view is pinned to the display view's bounds; an
existing attached player subview is removed first.

For a custom mode list, use the public mode classes and retain the same mode
instances for selection:

```swift
let normal = IRGLRenderMode2D()
normal.name = "Raw"
normal.shiftController.enabled = false

let panorama = IRGLRenderMode2DFisheye2Pano()
panorama.name = "Panorama"
panorama.contentMode = .scaleAspectFill
panorama.wideDegreeX = 360
panorama.wideDegreeY = 20

let fisheye = IRGLRenderMode3DFisheye()
fisheye.name = "Fisheye"
fisheye.parameter = IRFisheyeParameter(
    width: 0,
    height: 0,
    up: false,
    rx: 0,
    ry: 0,
    cx: 0,
    cy: 0,
    latmax: 80
)

let fourPanel = IRGLRenderModeMulti4P()
fourPanel.name = "Four lens"
fourPanel.parameter = fisheye.parameter

let modes: [IRGLRenderMode] = [panorama, fisheye, fourPanel, normal]
player.renderModes = modes
player.load(IRMediaSource(
    url: fisheyeURL,
    videoType: .custom,
    backendPreference: .ffmpeg
))
player.selectRenderMode(renderMode: panorama)
```

`selectRenderMode(renderMode:)` only accepts an instance currently contained
in `renderModes`; an unrelated new instance is rejected. The current instance
is available from `renderMode`. `contentMode` accepts
`.scaleAspectFit`, `.scaleAspectFill`, or `.scaleToFill`.

`IRFisheyeParameter` is a value-at-construction calibration object. Its
constructor takes source width/height, orientation, lens radii/centres, and
the latitude limit. Passing zero dimensions lets the fisheye program update
dimensions from the first frame when its automatic update behavior is active.

`snapshot()` returns a `UIImage?` from the display view. It may be `nil` only
when the display surface is unavailable; before the first render the current
implementation can return an empty placeholder image, so a non-`nil` value is
not proof that a frame has been displayed.

## Direct custom frame input

Create an `IRFFVideoInput` and include it in an FFmpeg `IRMediaSource`. The
player binds the input to its active output when the source is loaded. The URL
is still required as the session identity and format-context source.

`IRFFVideoInput.OutputType.displayView` (the default) hands frames to the
player's display view. `.decoder` binds to the active FFmpeg decoder's
video output instead of directly to the display view and exposes that output's
admission path. The input's weak `videoOutput` reference is managed by the
active player generation.

`IRVideoFrameRGB` is the application-facing frame constructor:

```swift
let input = IRFFVideoInput(outputType: .displayView)
player.load(IRMediaSource(
    url: sourceURL,
    videoInput: input,
    backendPreference: .ffmpeg
))

let width = 640
let height = 360
let bytesPerRow = width * 4
let data = Data(repeating: 0, count: bytesPerRow * height)

guard let frame = IRVideoFrameRGB(
    width: width,
    height: height,
    pixelFormat: .bgra32,
    bytesPerRow: bytesPerRow,
    data: data
) else {
    return
}

frame.position = 0
frame.duration = 1.0 / 30.0
if !input.trySend(videoFrame: frame) {
    // The input/output rejected and reclaimed the frame.
}
```

Use `.rgb24` for three bytes per pixel in red/green/blue order. Use `.bgra32`
for four bytes per pixel in blue/green/red/alpha order. A padded row stride is
valid when it is at least `width * bytesPerPixel`; the input `Data` must contain
at least `bytesPerRow * height` bytes. Invalid geometry or arithmetic returns
`nil` from the initializer.

`trySend(videoFrame:)` is a bounded admission operation and does not wait for
queue capacity. It briefly synchronizes access to the active output, so call it
from a producer queue rather than a latency-sensitive UI callback. If the
active output implements the optional admission method, `false` means that the
output is unavailable, the current generation was replaced, or its queue has
no capacity; the frame is reclaimed and must not be reused. The display view
currently exposes the legacy `send(videoFrame:)` method, so its fallback can
return `true` after handing the frame to the view without promising that a
renderable surface accepted it. `send(videoFrame:)` is a compatibility alias
with the same input-side behavior. `IRFFCVYUVVideoFrame(pixelBuffer:)` can wrap
an application-owned `CVPixelBuffer`. `IRFFAVYUVVideoFrame` is populated by the
FFmpeg software decoder; application code should not depend on its internal
plane writer.

## Custom packet decoding

Subclass `IRFFVideoInput` to intercept compressed packets. Routing is opt-in:
the base `shouldHandle` returns `false`, which leaves packets on the built-in
FFmpeg/VideoToolbox path.

```swift
final class CustomInput: IRFFVideoInput {
    override func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        packet: IRFFVideoPacketDescriptor
    ) -> Bool {
        packet.payloadByteCount > 0
    }

    override func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet: IRFFCompressedVideoPacket,
        completion: IRFFCustomVideoDecodeCompletion
    ) -> IRFFCustomVideoDecodeOutcome {
        // Decode packet.data using the application decoder.
        // Return .frame(frame), .dropped, or .failed(error) for synchronous
        // work. Retain completion and return .deferred for asynchronous work.
        return .dropped
    }
}
```

`IRFFVideoPacketDescriptor` is allocation-free routing metadata. It contains
payload and side-data counts, PTS/DTS ticks, duration ticks, stream index,
flags, key-frame status, and source position. After a source opts in,
`IRFFCompressedVideoPacket` owns the compressed payload and side-data bytes.
`IRFFVideoCodecDescriptor` owns codec identity, dimensions, pixel format,
profile, level, bitrate, and extradata. Convert ticks with
`IRFFVideoDecoderInfo.timebase`.

For asynchronous output, retain the supplied
`IRFFCustomVideoDecodeCompletion` before returning `.deferred`, then resolve it
exactly once:

```swift
// From retained asynchronous work:
_ = completion.send(videoFrame: frame)
// Or: _ = completion.drop()
// Or: _ = completion.fail(decoderError)
```

Releasing an unresolved completion automatically drops the reservation. Seek,
stop, replacement, and terminal decode errors invalidate old completions. A
late or duplicate completion is rejected; a newly supplied frame is reclaimed
unless it is the same frame instance already resolved. `maximumDecodeDuration`
limits built-in buffered output; it is not a timeout for custom asynchronous
work.

## Errors and legacy notifications

`IRError.error` contains the wrapped `NSError`. Load validation errors use the
`IRPlayer.Load` domain:

| Code | Cause |
| ---: | --- |
| 1 | `IRMediaSource.url` is `nil`. |
| 2 | The requested backend could not be constructed. |
| 3 | Explicit `.avFoundation` conflicts with headers, custom input, or a non-AVFoundation video type. |
| 4 | Automatic backend resolution found no supported backend. |

Backend open, decode, and rendering failures retain the backend's error data in
`IRError`; do not infer a load code for those errors.

Existing integrations can continue using NotificationCenter:

```swift
player.registerPlayerNotification(
    target: self,
    stateAction: #selector(stateChanged(_:)),
    progressAction: #selector(progressChanged(_:)),
    playableAction: #selector(playableChanged(_:)),
    errorAction: #selector(playbackFailed(_:))
)

// Remove all four registrations for this player and target.
player.removePlayerNotification(target: self)
```

The notification names are `IRPlayerStateChangeNotificationName`,
`IRPlayerProgressChangeNotificationName`,
`IRPlayerPlayableChangeNotificationName`, and
`IRPlayerErrorNotificationName`. The notification object is the player. Decode
the `userInfo` dictionary with the inherited `IRModel.state(fromUserInfo:)`,
`IRModel.progress(fromUserInfo:)`, `IRModel.playable(fromUserInfo:)`, or
`IRModel.error(fromUserInfo:)`; the public `IRPlayer*Key` constants identify
the fields. These notifications are emitted from the same event source and
are delivered on the main thread.

## Threading contract

The player facade and its view are UIKit-facing objects:

- Install the view, change frames, select modes, and update presentation from
  the main thread.
- Event handlers and legacy notifications run on the main thread.
- `load`, `play`, `pause`, `seekToTime`, and `stop` marshal their operation to
  the main thread. Coordinate calls with the owning UI lifecycle because the
  call can execute synchronously when invoked from a background thread.
- The decoder, queues, Metal renderer, and audio owners are internal runtime
  domains. Do not retain or call internal backend instances.
- Custom frame submission does not wait for queue capacity. Outputs that
  implement the admission method return `false` when they cannot accept a
  frame; feed from a producer queue and drop, coalesce, or retry later. The
  display-view fallback uses the legacy send method and may report `true` once
  the frame has been handed to the view.
- Custom packet values and deferred completions are designed for asynchronous
  work, but completion resolution remains one-shot and generation-bound.

## Security and deployment boundaries

The library accepts URLs and header dictionaries supplied by the application.
Use TLS-protected endpoints where the service supports them, keep credentials
out of URL query strings, and avoid placing real tokens in diagnostics or
sample code. Header-based credentials still require the FFmpeg transport review
below. `IRPlayerImp.Logger.delegate` receives
all library log messages; redact or restrict any sink that forwards them to
analytics or a remote service.

For sources resolved to FFmpeg (including sources with custom headers), an
HTTPS URL is not a library-level guarantee of certificate verification in this
candidate. The bundled FFmpeg input trust behavior is still under security
review; verify the deployed path or place a trust-checked transport/proxy in
front of it before production use. This guide does not claim security
acceptance.

IRPlayer-swift does not implement DRM, authentication policy, certificate
pinning, or credential storage. Application networking settings and
`URLSession` trust delegates do not govern the FFmpeg backend: FFmpeg opens its
own input transport, and this public API currently has no FFmpeg trust callback,
certificate-pinning hook, or custom-trust configuration. Configure controls in
the application/networking layer only for transports that the application
actually owns; for FFmpeg sources, use a trust-checked transport or proxy that
the player can consume, or verify the deployed FFmpeg path separately.

TLS/header forwarding security acceptance for the bundled FFmpeg path remains
unresolved. See the [release audit](../releases/2.0-release-audit.md) and
[FFmpeg update requirements](../releases/ffmpeg-update-requirements.md) before
shipping an FFmpeg URL, including HTTPS/HLS or custom-header sources. FFmpeg
currently forwards application-supplied headers through redirects and nested
HLS opens without an origin boundary, and the reviewed path permits HTTPS to
HTTP downgrade; do not send bearer tokens, cookies, or other secrets through
that path until those transport rules are remediated and tested. FFmpeg
decoding and custom frame injection also consume application-provided bytes;
validate untrusted media and keep custom decoder work bounded before submitting
frames.

## Migration checklist

For a 1.x integration:

1. Keep `IRPlayerImp.player()` and `replaceVideoWithURL` while migrating.
2. Move player-wide settings into `IRPlayerConfiguration`.
3. Replace URL/header/decoder mutation plus replacement with one
   `IRMediaSource` and `load(_:)` call.
4. Retain an `IRPlayerObservation` and migrate selector notifications to typed
   `IRPlayerEvent` handling when convenient.
5. Replace ambiguous `IRVideoFrameRGB(linesize:rgb:)` construction with the
   format-explicit `IRVideoFrameRGB(width:height:pixelFormat:bytesPerRow:data:)`
   initializer.
6. Replace pointer-based custom packet callbacks with
   `IRFFVideoPacketDescriptor`, `IRFFCompressedVideoPacket`, and
   `IRFFVideoCodecDescriptor` values.

Read the [migration guide](../releases/2.0-migration.md) (currently labelled
2.0) for before/after examples and ownership rules. The existing [2.0 release
notes](../releases/2.0.md) describe the historical compatibility layer; they do
not designate the version of this unreleased candidate.

## Validation

From the repository root, the supported local release acceptance command is:

```bash
Scripts/ci/run-acceptance.sh all
```

The workflow runs the Swift package manifest/build checks, a Release iOS
device build, the iOS simulator test suite, and the demo playback UI suite.
See the [release process](../releases/release-process.md) for CI triggers,
artifacts, branch rules, and tag delivery.
