import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRPlayerAPIv2Tests: XCTestCase {
    func testConfigurationProvidesSafeDefaultsAndNormalizesRanges() {
        var configuration = IRPlayerConfiguration(
            playableBufferInterval: -.infinity,
            volume: 2
        )

        XCTAssertEqual(configuration.playableBufferInterval, 2)
        XCTAssertEqual(configuration.volume, 1)
        XCTAssertFalse(configuration.autoplay)
        XCTAssertEqual(configuration.backgroundPolicy, .pauseAndResume)

        configuration.playableBufferInterval = -4
        configuration.volume = -1
        XCTAssertEqual(configuration.playableBufferInterval, 0)
        XCTAssertEqual(configuration.volume, 0)
    }

    func testMediaSourceResolvesAutomaticAndExplicitBackendPreferences() {
        let decoder = IRPlayerDecoder.defaultDecoder()
        let mp4URL = URL(string: "https://example.com/video.mp4")!

        XCTAssertEqual(IRMediaSource(url: mp4URL).decoderType(using: decoder), .avPlayer)
        XCTAssertEqual(
            IRMediaSource(url: mp4URL, backendPreference: .ffmpeg).decoderType(using: decoder),
            .ffmpeg
        )
        XCTAssertEqual(
            IRMediaSource(url: mp4URL, backendPreference: .avFoundation).decoderType(using: decoder),
            .avPlayer
        )
        XCTAssertEqual(
            IRMediaSource(
                url: mp4URL,
                headers: ["Authorization": "token"]
            ).backendResolution(using: decoder),
            .backend(.ffmpeg)
        )
        XCTAssertEqual(
            IRMediaSource(
                url: mp4URL,
                headers: ["Authorization": "token"],
                backendPreference: .avFoundation
            ).backendResolution(using: decoder),
            .unsupportedAVFoundation
        )
        XCTAssertEqual(IRMediaSource.empty.decoderType(using: decoder), .error)
    }

    func testAutomaticSourceDistinguishesUnsupportedURLFromMissingURL() {
        let decoder = IRPlayerDecoder.defaultDecoder()
        decoder.unkonwnFormat = .error
        let unsupportedURLs = [
            URL(string: "custom://example.com/media")!,
            URL(
                string: "https://example.com/video.unknown"
            )!
        ]

        XCTAssertEqual(
            IRMediaSource(url: nil).backendResolution(
                using: decoder
            ),
            .missingURL
        )
        for url in unsupportedURLs {
            XCTAssertEqual(
                IRMediaSource(url: url).backendResolution(
                    using: decoder
                ),
                .unsupportedSource
            )
        }
    }

    func testConfigurationInitializerAppliesPlayerWideBehavior() {
        let configuration = IRPlayerConfiguration(
            decoder: .FFmpegDecoder(),
            autoplay: true,
            isLiveStream: true,
            playableBufferInterval: 0.4,
            volume: 0.25,
            gravityMode: .resizeAspectFill,
            displayMode: .box,
            backgroundPolicy: .continuePlayback
        )

        let player = IRPlayer(configuration: configuration)
        player.manager = nil

        XCTAssertTrue(player.decoder === configuration.decoder)
        XCTAssertTrue(player.configuration.autoplay)
        XCTAssertTrue(player.isLiveStream)
        XCTAssertEqual(player.playableBufferInterval, 0.4)
        XCTAssertEqual(player.volume, 0.25)
        XCTAssertEqual(player.viewGravityMode, .resizeAspectFill)
        XCTAssertEqual(player.displayMode, .box)
        XCTAssertEqual(player.configuration.backgroundPolicy, .continuePlayback)
    }

    func testDirectPlayerSettingsAreNormalizedLikeConfiguration() {
        let player = IRPlayer()
        player.manager = nil

        player.playableBufferInterval = -.infinity
        player.volume = 2

        XCTAssertEqual(player.playableBufferInterval, 2)
        XCTAssertEqual(player.volume, 1)

        player.playableBufferInterval = -4
        player.volume = -1
        XCTAssertEqual(player.playableBufferInterval, 0)
        XCTAssertEqual(player.volume, 0)
    }

    func testEmptyLoadEmitsFailureAndStopExposesStablePublicSnapshot() {
        let player = IRPlayer()
        player.manager = nil
        player.setRequestHeaderFields(["Authorization": "token"])
        let failure = expectation(description: "invalid source failure")
        var eventOrder: [String] = []
        let observation = player.observeEvents { event in
            switch event {
            case .stateChanged:
                eventOrder.append("state")
            case let .progress(snapshot):
                XCTAssertEqual(
                    snapshot,
                    IRPlayerTimeSnapshot(
                        current: 0,
                        total: 0,
                        fraction: 0
                    )
                )
                eventOrder.append("progress")
            case let .playable(snapshot):
                XCTAssertEqual(
                    snapshot,
                    IRPlayerTimeSnapshot(
                        current: 0,
                        total: 0,
                        fraction: 0
                    )
                )
                eventOrder.append("playable")
            case let .failure(error):
                XCTAssertEqual(error.error.domain, "IRPlayer.Load")
                XCTAssertEqual(error.error.code, 1)
                eventOrder.append("failure")
                failure.fulfill()
            }
        }

        player.load(.empty)
        wait(for: [failure], timeout: 1)
        player.stop()

        XCTAssertEqual(
            eventOrder,
            ["state", "progress", "playable", "failure"]
        )
        XCTAssertNil(player.mediaSource)
        XCTAssertNil(player.contentHeaders)
        XCTAssertNil(player.activeBackend)
        XCTAssertEqual(player.state, .none)
        XCTAssertEqual(player.progress, 0)
        XCTAssertEqual(player.duration, 0)
        XCTAssertEqual(player.playableTime, 0)
        XCTAssertFalse(player.isSeeking)
        withExtendedLifetime(observation) {}
    }

    func testObjectiveCFacadeSelectorsMatchTheCompatibilityContract() {
        let player = IRPlayerImp()
        player.manager = nil
        let supportedSelectors = [
            "play",
            "pause",
            "stop",
            "replaceEmpty",
            "seekToTime:completeHandler:",
            "setRequestHeaderFields:",
            "replaceVideoWithURL:videoType:"
        ]

        for selectorName in supportedSelectors {
            XCTAssertTrue(
                player.responds(
                    to: NSSelectorFromString(selectorName)
                ),
                "Missing Objective-C selector \(selectorName)"
            )
        }
        XCTAssertFalse(
            player.responds(
                to: NSSelectorFromString(
                    "selectAudioTrackIndex:"
                )
            )
        )
        XCTAssertFalse(
            player.responds(
                to: NSSelectorFromString(
                    "replaceVideoWithURL:videoType:videoInput:"
                )
            )
        )
    }
}
