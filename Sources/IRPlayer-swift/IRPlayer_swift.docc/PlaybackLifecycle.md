# Playback lifecycle

The player owns one active source and one backend generation at a time. A load
whose backend activates replaces the previous source; source validation or
backend-construction errors reset the session and report a load error;
``IRPlayerImp/stop()`` clears it without an input error. Do not retain or call
backend objects—the facade is the public control surface.

## Load and control playback

```swift
let source = IRMediaSource(
    url: streamURL,
    headers: [:],
    videoType: .vr,
    backendPreference: .ffmpeg
)

player.load(source, autoplay: false)
player.play()
player.pause()
player.seekToTime(time: 30) { completed in
    print("seek admitted:", completed)
}
player.stop()
```

``IRPlayerImp/seekToTime(time:completeHandler:)`` calls its completion with
`false` when the request cannot be admitted or a later replacement/stop
invalidates it. ``IRPlayerImp/load(_:autoplay:)`` and the playback commands
marshal synchronously to the main thread when called from another thread; UI
callers should still coordinate them with their view lifecycle.

The read-only snapshots ``IRPlayerImp/state``, ``IRPlayerImp/progress``,
``IRPlayerImp/duration``, ``IRPlayerImp/playableTime``,
``IRPlayerImp/presentationSize``, ``IRPlayerImp/isSeeking``, and
``IRPlayerImp/activeBackend`` describe the active generation. A live stream or
unknown duration can report a zero duration.

## Choose a backend

``IRPlaybackBackendPreference/automatic`` is the recommended default. The
source is resolved before a backend is constructed:

| Source condition | Automatic result |
| --- | --- |
| Non-empty `headers` | FFmpeg |
| `videoInput` is present | FFmpeg |
| `videoType` is `.fisheye`, `.pano`, or `.custom` | FFmpeg |
| `.mp4` with `.normal` or `.vr` | The decoder's MP4 rule; AVFoundation by default |
| `.m3u8` with `.normal` or `.vr` | AVFoundation by default |
| RTSP, RTMP, or FLV | FFmpeg by default |
| Unknown URL | The decoder's unknown-format rule; FFmpeg by default |

Format matching is case-insensitive and checks the URL string/path. Use an
explicit preference when the URL does not identify its format:

```swift
player.load(IRMediaSource(
    url: localFileURL,
    backendPreference: .ffmpeg
))
```

``IRPlayerDecoder/defaultDecoder()`` provides the standard rules.
``IRPlayerDecoder/FFmpegDecoder()`` routes recognized formats to FFmpeg, and
``IRPlayerDecoder/AVPlayerDecoder()`` supplies an AVFoundation rule set. The
underlying backend still has to support the resulting source. Non-empty custom
headers, custom input, and non-normal/non-VR presentation types cannot be
combined with an explicit ``IRPlaybackBackendPreference/avFoundation`` source;
such a source reports load error code 3.

## Observe typed events

Use ``IRPlayerImp/observeEvents(_:)`` to receive state, progress, playable, and
failure values through ``IRPlayerEvent``:

```swift
observation = player.observeEvents { event in
    switch event {
    case let .stateChanged(previous, current):
        print(previous, "->", current)
    case let .progress(time), let .playable(time):
        print(time.current, time.total, time.fraction)
    case let .failure(error):
        print(error.error.domain, error.error.code)
    }
}
```

``IRPlayerTimeSnapshot/fraction`` is normalized to `0...1`. Its `current` and
`total` values are finite and non-negative; `total` may be zero for live or
not-yet-known duration. The observation token does not keep the player alive.
