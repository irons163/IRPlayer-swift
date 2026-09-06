# Custom video input

Use ``IRFFVideoInput`` when an application supplies decoded frames or owns a
compressed video decoder. Include the input in an ``IRMediaSource`` with an
FFmpeg-compatible URL and backend preference. The URL identifies the playback
session and supplies the format context; it is still required by
``IRPlayerImp/load(_:autoplay:)``.

``IRFFVideoInput/OutputType/displayView`` (the default) hands frames to the
player's display view. ``IRFFVideoInput/OutputType/decoder`` binds to the
active FFmpeg decoder's video output instead of directly to the display view
and exposes that output's admission path. The input's weak `videoOutput`
reference is managed by the active player generation.

## Submit decoded frames

``IRVideoFrameRGB`` is the application-facing constructor for packed RGB data.
It validates dimensions, row stride, and data length before a frame can be
submitted:

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
let bytes = Data(repeating: 0, count: bytesPerRow * height)

guard let frame = IRVideoFrameRGB(
    width: width,
    height: height,
    pixelFormat: .bgra32,
    bytesPerRow: bytesPerRow,
    data: bytes
) else { return }

frame.position = 0
frame.duration = 1.0 / 30.0
let accepted = input.trySend(videoFrame: frame)
```

Use ``IRRGBPixelFormat/rgb24`` for three-byte RGB rows or
``IRRGBPixelFormat/bgra32`` for four-byte BGRA rows. A padded `bytesPerRow` is
valid when it is at least the minimum row size. ``IRFFVideoInput/trySend(videoFrame:)``
is a bounded admission operation and does not wait for queue capacity. It
briefly synchronizes access to the active output, so call it from a producer
queue rather than a latency-sensitive UI callback. When the active output
implements the optional admission method, `false` means the frame was rejected
and reclaimed, so do not reuse or submit that frame again. The display view
currently exposes only the legacy `send(videoFrame:)` method; its fallback can
return `true` after handing the frame to the view without promising that a
renderable surface accepted it. ``IRFFVideoInput/send(videoFrame:)`` is a
compatibility alias with the same input-side behavior.

``IRFFCVYUVVideoFrame`` can wrap an application-owned `CVPixelBuffer`.
``IRFFAVYUVVideoFrame`` is populated by the FFmpeg software decoder; its plane
writer is not application-facing API.

## Intercept compressed packets

Subclass ``IRFFVideoInput`` and override both methods when a custom decoder
should receive packets. The base ``IRFFVideoInput/shouldHandle(_:packet:)``
returns `false`, leaving packets on the built-in path.

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
        // Decode packet.data synchronously, or retain completion and return
        // .deferred for asynchronous work.
        return .dropped
    }
}
```

``IRFFVideoPacketDescriptor`` contains packet metadata without exposing FFmpeg
pointers. ``IRFFCompressedVideoPacket`` owns compressed payload and side-data
bytes. ``IRFFVideoCodecDescriptor`` and ``IRFFVideoDecoderInfo`` describe the
codec, timebase, frame rate, and hardware-decoding setting.

For asynchronous decoding, retain the supplied
``IRFFCustomVideoDecodeCompletion`` before returning `.deferred`, then resolve
it exactly once:

```swift
// From retained asynchronous work:
_ = completion.send(videoFrame: frame)
// Or: _ = completion.drop()
// Or: _ = completion.fail(decoderError)
```

Seek, stop, replacement, and terminal decode errors invalidate old
completions. A late or duplicate completion is rejected; a newly supplied
frame is reclaimed unless it is the same frame instance already resolved.
Releasing an unresolved completion drops its reservation.
