# Errors and compatibility

## Load errors

Observe ``IRPlayerEvent/failure(_:)`` and inspect ``IRError/error``. Load
validation errors use the `IRPlayer.Load` domain:

| Code | Meaning |
| ---: | --- |
| 1 | The source URL is missing. |
| 2 | The requested backend could not be constructed. |
| 3 | Explicit AVFoundation selection conflicts with headers, custom input, or a non-AVFoundation video type. |
| 4 | Automatic backend resolution found no supported backend. |

Backend open, decode, and rendering failures retain backend error data in
``IRError``; do not infer one of these load codes for every runtime failure.
Call ``IRPlayerImp/stop()`` when the intention is to clear playback instead of
reporting a missing source.

## Notification compatibility

Existing Objective-C integrations can continue to use the NotificationCenter
bridge:

```swift
player.registerPlayerNotification(
    target: self,
    stateAction: #selector(stateChanged(_:)),
    progressAction: #selector(progressChanged(_:)),
    playableAction: #selector(playableChanged(_:)),
    errorAction: #selector(playbackFailed(_:))
)

player.removePlayerNotification(target: self)
```

The notification names are `IRPlayerStateChangeNotificationName`,
`IRPlayerProgressChangeNotificationName`,
`IRPlayerPlayableChangeNotificationName`, and
`IRPlayerErrorNotificationName`. Decode their `userInfo` values with the
inherited parsers ``IRModel/state(fromUserInfo:)``,
``IRModel/progress(fromUserInfo:)``, ``IRModel/playable(fromUserInfo:)``, and
``IRModel/error(fromUserInfo:)``. Prefer ``IRPlayerImp/observeEvents(_:)`` for
new Swift code.

## Migration boundaries

For a 1.x integration, keep ``IRPlayerImp/player()`` and
``IRPlayerImp/replaceVideoWithURL(contentURL:videoType:)`` while migrating.
Move settings to ``IRPlayerConfiguration``, replace URL/header mutation with
``IRMediaSource`` plus ``IRPlayerImp/load(_:autoplay:)``, and retain an
``IRPlayerObservation`` when moving from selectors to typed events. For custom
frames, use the format-explicit ``IRVideoFrameRGB`` initializer or
``IRFFCVYUVVideoFrame`` instead of relying on internal I420 plane writers. For
custom packets, use the value types documented in <CustomVideoInput> rather
than pointer-based callbacks.

## Threading and security

The player and its view are UIKit-facing objects. Install the view, change
frames, select modes, and update presentation on the main thread. Event
handlers and legacy notifications run on the main thread. Custom frame
submission does not wait for queue capacity. Outputs that implement the
admission method return `false` when they cannot accept a frame; feed from a
producer queue and drop or retry later. The display-view fallback uses the
legacy send method and may report `true` once the frame has been handed to the
view. Custom packet completions are one-shot and generation-bound.

Use TLS-protected endpoints where available, keep credentials out of URL query
strings, and treat URLs, headers, errors, and log messages as sensitive data.
Header-based credentials still require the FFmpeg transport review below.
`IRPlayerImp.Logger.delegate` receives library logs, so redact or restrict any
logging sink forwarded to analytics. The library does
not provide DRM, authentication policy, certificate pinning, or credential
storage. Application networking settings and `URLSession` trust delegates do
not govern the FFmpeg backend: FFmpeg opens its own input transport, and this
public API currently has no FFmpeg trust callback, certificate-pinning hook, or
custom-trust configuration. Configure controls in the application/networking
layer only for transports the application actually owns.

For sources resolved to FFmpeg, including sources with custom headers, an
HTTPS URL is not a library-level guarantee of certificate verification in this
candidate. TLS/header forwarding security acceptance for the bundled FFmpeg
path remains under review; use a trust-checked transport or proxy that the
player can consume, or verify the deployed FFmpeg path separately, before
production use. The reviewed path currently forwards supplied headers through
redirects and nested HLS opens without an origin boundary and permits
HTTPS-to-HTTP downgrade; do not pass bearer tokens, cookies, or other secrets
until those transport rules are remediated and tested. This catalog does not
claim security acceptance. The repository release audit and FFmpeg update
requirements contain the current release gate for this review.
