[![CI](https://github.com/irons163/IRPlayer-swift/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/irons163/IRPlayer-swift/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/Platform-iOS-blue.svg)

# IRPlayer-swift

IRPlayer-swift is an iOS video playback framework with a Swift-first player
facade, AVFoundation and FFmpeg backends, and a shared UIKit display view that
hosts AVPlayerLayer or Metal rendering for flat, VR, fisheye, panorama,
distortion, and multi-view content.

The current development line supports iOS 15 and later. The package product is
`IRPlayer`; the Swift module is `IRPlayerSwift`. This README describes the
current source, while the published `2.0` tag predates the API redesign. Pin
the exact release or candidate ref reviewed by your application.

## Capabilities

- AVFoundation playback for supported local and network media.
- FFmpeg playback for RTSP, RTMP, FLV, custom headers, custom input, and
  presentation types not handled by AVFoundation.
- Typed sources, configuration, state/progress/playable/error events, and
  read-only playback snapshots.
- Metal modes for normal 2D, VR, VR Box, fisheye, fisheye-to-panorama, and
  four-panel output.
- Format-explicit RGB/Core Video frame input and value-based custom packet
  decoding hooks.
- A retained legacy facade and selector-based notification bridge for existing
  integrations. Custom frame and decoder APIs require the [migration
  guide](docs/releases/2.0-migration.md).

## Requirements and installation

- iOS 15 or later.
- Xcode 26 or later to build the current source and run the acceptance suite.
  The VideoToolbox integration uses `VTDecodeInfoFlags.frameInterrupted`,
  which is unavailable in the older Xcode 16.4 SDK.
- Swift Package Manager. The package includes the FFmpeg wrapper and prebuilt
  iOS FFmpeg XCFrameworks; it does not expose a macOS playback target.

In Xcode, add this repository as a package dependency and select the `IRPlayer`
library product. For a Swift package manifest, this branch tracks the current
candidate line and is intentionally explicit so the snippet is valid
`PackageDescription`:

```swift
dependencies: [
    .package(
        url: "https://github.com/irons163/IRPlayer-swift.git",
        branch: "codex/2.0-refactor-stack"
    )
]
```

Use the exact reviewed revision or the release requirement chosen for your
application when the candidate is published. Then import the Swift module:

```swift
import IRPlayerSwift
```

## Quick start

`IRPlayer` is a typealias for the public `IRPlayerImp` facade. A player
creates its display view during initialization. Retain the player and its event
observation for the lifetime of the screen:

```swift
import UIKit
import IRPlayerSwift

final class PlayerViewController: UIViewController {
    private let player = IRPlayer(configuration: IRPlayerConfiguration(
        autoplay: true
    ))
    private var observation: IRPlayerObservation?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let playerView = player.view else { return }
        playerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        observation = player.observeEvents { event in
            switch event {
            case let .stateChanged(_, current):
                print("state:", current)
            case let .progress(snapshot):
                print("progress:", snapshot.current, "/", snapshot.total)
            case let .playable(snapshot):
                print("playable through:", snapshot.current)
            case let .failure(error):
                print("playback failed:", error.error)
            }
        }

        guard let url = URL(string: "https://example.com/video.mp4") else {
            return
        }
        player.load(IRMediaSource(url: url))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player.stop()
    }
}
```

Event handlers are delivered on the main thread. Keep the
`IRPlayerObservation` token while events are needed; calling `cancel()` or
releasing it ends that observation. Call `stop()` to clear playback without an
input error. A source with a missing URL resets the current session and reports
a typed load error.

## API map

The [SDK guide](docs/sdk/README.md) contains the complete public contract,
backend rules, ownership boundaries, and migration recipes. The [DocC
catalog](Sources/IRPlayer-swift/IRPlayer_swift.docc/IRPlayer_swift.md) provides
the same material as browsable Xcode documentation.

| Need | Start here |
| --- | --- |
| Configure and load media | `IRPlayerConfiguration`, `IRMediaSource`, and the [lifecycle guide](Sources/IRPlayer-swift/IRPlayer_swift.docc/PlaybackLifecycle.md) |
| Select AVFoundation or FFmpeg | `IRPlaybackBackendPreference` and the [backend rules](docs/sdk/README.md#backend-rules) |
| Handle state, progress, playable time, and failures | `IRPlayerEvent` and `IRPlayerObservation` |
| Render normal, VR, fisheye, panorama, or custom modes | `IRVideoType` and the [rendering guide](Sources/IRPlayer-swift/IRPlayer_swift.docc/RenderingModes.md) |
| Feed application-owned frames | `IRFFVideoInput` and the [custom input guide](Sources/IRPlayer-swift/IRPlayer_swift.docc/CustomVideoInput.md) |
| Migrate selector notifications or old replacement calls | [Migration and compatibility](Sources/IRPlayer-swift/IRPlayer_swift.docc/ErrorsAndCompatibility.md) |

Custom frame submission has a bounded admission result; use a producer queue
and handle a `false` result by dropping or retrying later. The detailed guide
documents the display-view fallback, decoder output, generation invalidation,
one-shot deferred decode completions, and load error codes.

Security note: for FFmpeg-selected sources, including custom-header sources,
HTTPS alone is not a library-level certificate-verification guarantee in this
candidate. The FFmpeg backend opens its own transport; application
`URLSession` trust settings do not govern it, and this public API has no
FFmpeg pinning or custom-trust hook. See the [SDK security boundaries](docs/sdk/README.md#security-and-deployment-boundaries),
[release audit](docs/releases/2.0-release-audit.md), and [FFmpeg update
requirements](docs/releases/ffmpeg-update-requirements.md); complete the
pending trust, redirect, and header-scope review before production use. The
reviewed FFmpeg path currently forwards supplied headers through redirects and
nested HLS opens without an origin boundary and permits HTTPS-to-HTTP downgrade;
do not pass bearer tokens, cookies, or other secrets until those transport
rules are remediated and tested.

## Demo and validation

The [SPMDemo](SPMDemo/) app contains local-media playback and the eight rendering
acceptance scenarios. The supported local release acceptance command is:

```bash
Scripts/ci/run-acceptance.sh all
```

See the [release process](docs/releases/release-process.md) for CI gates,
artifacts, branch rules, and tag delivery. Do not treat the existing published
`2.0` release as the current redesigned API; its migration notes are retained
for comparison while the next version is decided.

Related integrations from the project ecosystem include
[IRPlayerUIShell](https://github.com/irons163/IRPlayerUIShell),
[IRIPCamera](https://github.com/irons163/IRIPCamera),
[IREffectPlayer](https://github.com/irons163/IREffectPlayer), and
[IRLive](https://github.com/irons163/IRLive). These projects may target older
facade or rendering APIs; check the migration guide before reusing their code.

## Screenshots

| Normal | VR | VR Box | Fisheye |
|:---:|:---:|:---:|:---:|
| ![Normal](SPMDemo/ScreenShots/demo1.PNG) | ![VR](SPMDemo/ScreenShots/demo2.PNG) | ![VR Box](SPMDemo/ScreenShots/demo3.PNG) | ![Fisheye](SPMDemo/ScreenShots/demo4.PNG) |

| Panorama | Mode selection | Multi-window |
|:---:|:---:|:---:|
| ![Panorama](SPMDemo/ScreenShots/demo5.PNG) | ![Mode selection](SPMDemo/ScreenShots/demo6.PNG) | ![Multi-window](SPMDemo/ScreenShots/demo7.PNG) |

## Credits

Some foundational code originated in [SGPlayer](https://github.com/libobjc/SGPlayer).
The bundled XCFrameworks use FFmpeg 6.1.6 with GnuTLS 3.8.13, Apple SecTrust,
and the reviewed transport security patches. Build provenance and third-party
notices are documented in the [FFmpeg bundle guide](Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/README.md).
Earlier bundles originated from [ffmpeg-kit](https://github.com/arthenica/ffmpeg-kit).
