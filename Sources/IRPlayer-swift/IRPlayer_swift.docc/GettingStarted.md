# Getting started

Add the `IRPlayer` library product from the Swift package and import the
`IRPlayerSwift` module in application code. The package supports iOS 15 and
later and uses a shared UIKit display surface. Normal AVFoundation playback
uses an AVPlayerLayer; FFmpeg and immersive/custom modes use Metal renderers.

## Create a player

``IRPlayer`` is a typealias for ``IRPlayerImp``. The initializer creates the
``IRPLFView`` display surface used by the player. Add ``IRPlayerImp/view`` to your
view hierarchy and retain the player for as long as the screen owns playback.

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
                print("progress:", snapshot.current, snapshot.total)
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

Retain ``IRPlayerObservation`` while events are needed. Its ``IRPlayerObservation/cancel()``
method is idempotent, and releasing the token also cancels the observation.
Event handlers are delivered on the main thread.

## Configure before loading

Use ``IRPlayerConfiguration`` for player-wide defaults and
``IRMediaSource`` for each load. The configuration defaults to automatic
backend selection, no autoplay, a two-second playable buffer interval, full
volume, aspect-fit gravity, normal display mode, and pause-and-resume when the
application backgrounds.

```swift
let player = IRPlayer(configuration: IRPlayerConfiguration(
    autoplay: false,
    playableBufferInterval: 2,
    gravityMode: .resizeAspect,
    displayMode: .normal
))

let source = IRMediaSource(
    url: videoURL,
    videoType: .normal,
    backendPreference: .automatic
)
player.load(source, autoplay: true)
```

The `autoplay` argument on ``IRPlayerImp/load(_:autoplay:)`` overrides the
configuration for that load. Use ``IRPlayerImp/stop()`` to clear playback
without reporting invalid input; loading a source whose URL is `nil` resets the
current session and reports a typed load error.
