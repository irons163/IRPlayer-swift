import XCTest
import UIKit
@testable import IRPlayer_swift

final class IRPlayerImpLazyPlayerTests: XCTestCase {

    func testPlayerVolumeConvertsFiniteValues() {
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: 0.5), 0.5, accuracy: 0.0001)
    }

    func testPlayerVolumeDefaultsNilAndNonFiniteValuesToZero() {
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: nil), 0)
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: .nan), 0)
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: .infinity), 0)
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: -1), 0)
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: 2), 1)
    }

    func testLazyPlayerFactoriesReturnExistingPlayersOrCreateNewOnes() {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil

        let existingAVPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        XCTAssertTrue(IRPlayerImp.makeAVPlayerIfNeeded(existingAVPlayer, abstractPlayer: abstractPlayer) === existingAVPlayer)

        let createdAVPlayer = IRPlayerImp.makeAVPlayerIfNeeded(nil, abstractPlayer: abstractPlayer)
        XCTAssertTrue(createdAVPlayer.abstractPlayer === abstractPlayer)

        let existingFFPlayer = IRFFPlayer.player(with: abstractPlayer)
        XCTAssertTrue(IRPlayerImp.makeFFPlayerIfNeeded(existingFFPlayer, abstractPlayer: abstractPlayer) === existingFFPlayer)

        let createdFFPlayer = IRPlayerImp.makeFFPlayerIfNeeded(nil, abstractPlayer: abstractPlayer)
        XCTAssertTrue(createdFFPlayer.abstractPlayer === abstractPlayer)

        withExtendedLifetime((existingAVPlayer, createdAVPlayer, existingFFPlayer, createdFFPlayer, abstractPlayer)) {}
    }

    func testPlaybackPropertiesFallBackToDefaultsForEmptyReplacement() {
        let player = IRPlayerImp.player()
        player.manager = nil

        player.replaceEmpty()

        XCTAssertEqual(player.state, .none)
        XCTAssertEqual(player.presentationSize, .zero)
        XCTAssertEqual(player.bitrate, 0)
        XCTAssertEqual(player.progress, 0)
        XCTAssertEqual(player.duration, 0)
        XCTAssertEqual(player.playableTime, 0)
        XCTAssertFalse(player.seeking)
        withExtendedLifetime(player) {}
    }

    func testPlaybackPropertiesReadAVPlayerReplacementDefaults() {
        let player = IRPlayerImp.player()
        player.manager = nil
        player.decoder = IRPlayerDecoder.AVPlayerDecoder()

        player.replaceVideoWithURL(contentURL: NSURL(string: "https://example.com/video.mp4"))

        XCTAssertEqual(player.state, .none)
        XCTAssertEqual(player.presentationSize, .zero)
        XCTAssertEqual(player.bitrate, 0)
        XCTAssertEqual(player.progress, 0)
        XCTAssertEqual(player.duration, 0)
        XCTAssertEqual(player.playableTime, 0)
        XCTAssertFalse(player.seeking)
        withExtendedLifetime(player) {}
    }

    func testPlaybackPropertiesReadFFmpegReplacementDefaults() {
        let player = IRPlayerImp.player()
        player.manager = nil
        player.decoder = IRPlayerDecoder.FFmpegDecoder()

        player.replaceVideoWithURL(contentURL: NSURL(fileURLWithPath: "/tmp/missing.flv"))

        XCTAssertNotEqual(player.state, .playing)
        XCTAssertEqual(player.presentationSize, .zero)
        XCTAssertEqual(player.bitrate, 0)
        XCTAssertEqual(player.progress, 0)
        XCTAssertEqual(player.duration, 0)
        XCTAssertEqual(player.playableTime, 0)
        XCTAssertFalse(player.seeking)
        withExtendedLifetime(player) {}
    }

    func testViewConfigurationForwardsToDisplayView() throws {
        let player = IRPlayerImp.player()
        player.manager = nil
        let displayView = try XCTUnwrap(player.view as? IRGLView)
        let firstMode = IRGLRenderMode2D()
        let secondMode = IRGLRenderMode2D()

        player.renderModes = [firstMode, secondMode]
        player.selectRenderMode(renderMode: secondMode)
        player.viewGravityMode = .resizeAspectFill
        player.updateGraphicsViewFrame(frame: CGRect(x: 1, y: 2, width: 120, height: 80))

        XCTAssertEqual(player.renderModes?.count, 2)
        XCTAssertTrue(displayView.getCurrentRenderMode() === secondMode)
        XCTAssertEqual(displayView.frame, CGRect(x: 1, y: 2, width: 120, height: 80))
        withExtendedLifetime(player) {}
    }

    func testSetupPlayerViewReplacesExistingPlayerSubviews() throws {
        let player = IRPlayerImp.player()
        player.manager = nil
        let container = try XCTUnwrap(player.view)
        let firstSubview = UIView()
        let secondSubview = UIView()

        player.setupPlayerView(firstSubview)
        player.setupPlayerView(secondSubview)

        XCTAssertFalse(secondSubview.translatesAutoresizingMaskIntoConstraints)
        XCTAssertNil(firstSubview.superview)
        XCTAssertTrue(secondSubview.superview === container)
        XCTAssertEqual(container.subviews, [secondSubview])
        withExtendedLifetime(player) {}
    }

    func testControlWrappersAreCallableWithoutDecoderTarget() {
        let player = IRPlayerImp.player()
        player.manager = nil
        let seekFinished = expectation(
            description: "inactive seek reports failure"
        )
        defer {
            player.pause()
        }

        player.volume = 0.25
        player.setRequestHeaderFields(["Authorization": "token"])
        player.play()
        player.seekToTime(time: 12.5) { finished in
            XCTAssertFalse(finished)
            seekFinished.fulfill()
        }
        wait(for: [seekFinished], timeout: 1)
        player.seekToTime(time: 12.5)
        player.pause()

        XCTAssertEqual(player.snapshot()?.size, .zero)
        XCTAssertEqual(player.contentHeaders, ["Authorization": "token"])
        XCTAssertEqual(player.volume, 0.25)
        withExtendedLifetime(player) {}
    }

    func testNotificationRegistrationTargetsMatchingPlayerAndCanRemove() {
        let player = IRPlayerImp.player()
        player.manager = nil
        let recorder = PlayerNotificationRecorder()

        player.registerPlayerNotification(target: nil,
                                          stateAction: #selector(PlayerNotificationRecorder.didReceiveState(_:)))
        player.registerPlayerNotification(target: recorder,
                                          stateAction: #selector(PlayerNotificationRecorder.didReceiveState(_:)),
                                          progressAction: #selector(PlayerNotificationRecorder.didReceiveProgress(_:)),
                                          playableAction: #selector(PlayerNotificationRecorder.didReceivePlayable(_:)),
                                          errorAction: #selector(PlayerNotificationRecorder.didReceiveError(_:)))

        postPlayerNotification(IRPlayerStateChangeNotificationName, object: player)
        postPlayerNotification(IRPlayerProgressChangeNotificationName, object: player)
        postPlayerNotification(IRPlayerPlayableChangeNotificationName, object: player)
        postPlayerNotification(IRPlayerErrorNotificationName, object: player)
        postPlayerNotification(IRPlayerStateChangeNotificationName, object: IRPlayerImp.player())

        XCTAssertEqual(recorder.stateCount, 1)
        XCTAssertEqual(recorder.progressCount, 1)
        XCTAssertEqual(recorder.playableCount, 1)
        XCTAssertEqual(recorder.errorCount, 1)

        player.removePlayerNotification(target: recorder)
        postPlayerNotification(IRPlayerStateChangeNotificationName, object: player)

        XCTAssertEqual(recorder.stateCount, 1)
        withExtendedLifetime((player, recorder)) {}
    }

    func testLoggerDelegateReceivesEveryLogLevel() {
        let recorder = PlayerLoggerRecorder()
        let logger = IRPlayerLogger(subsystem: "IRPlayerTests", category: "unit")
        IRPlayerImp.Logger.delegate = recorder
        defer {
            IRPlayerImp.Logger.delegate = nil
        }

        logger.debug("debug message")
        logger.info("info message")
        logger.warning("warning message")
        logger.error("error message")

        XCTAssertEqual(recorder.records.map(\.level), [.debug, .info, .warning, .error])
        XCTAssertEqual(recorder.records.map(\.message), ["debug message", "info message", "warning message", "error message"])
        XCTAssertEqual(recorder.records.map(\.category), Array(repeating: "unit", count: 4))
    }

    func testBoxVRConfigurationAndDelegateCallbacksAreCallable() throws {
        let player = IRPlayerImp.player()
        player.manager = nil
        player.displayMode = .box

        player.replaceVideoWithURL(contentURL: nil, videoType: .vr)
        player.glViewWillBeginZooming(nil)
        player.glViewWillBeginDragging(nil)
        player.glViewDidEndDragging(nil, willDecelerate: true)
        player.glViewDidEndDragging(nil, willDecelerate: false)
        player.glViewDidEndZooming(nil, atScale: 1.25)
        player.glViewDidEndDecelerating(nil)

        let currentMode = try XCTUnwrap(player.renderModes?.first)
        XCTAssertTrue(currentMode is IRGLRenderModeDistortion)
        XCTAssertEqual(player.viewGravityMode, .resizeAspect)
        player.glViewWillBeginZooming(nil)
        withExtendedLifetime(player) {}
    }

    func testChangingDisplayModeReconfiguresCurrentVRPresentation() throws {
        let player = IRPlayerImp.player()
        player.manager = nil
        player.replaceVideoWithURL(contentURL: nil, videoType: .vr)
        XCTAssertTrue(try XCTUnwrap(player.renderModes?.first) is IRGLRenderModeVR)

        player.displayMode = .box

        XCTAssertTrue(try XCTUnwrap(player.renderModes?.first) is IRGLRenderModeDistortion)
        XCTAssertNotNil(player.displayView?.abstractPlayer)
        withExtendedLifetime(player) {}
    }

#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
    func testLifecycleNotificationHandlersAreCallableForInactivePlayer() {
        let player = IRPlayerImp.player()
        player.manager = nil

        player.applicationDidEnterBackground(NSNotification(name: UIApplication.didEnterBackgroundNotification))
        player.applicationWillEnterForeground(NSNotification(name: UIApplication.willEnterForegroundNotification))

        XCTAssertEqual(player.state, .none)
        withExtendedLifetime(player) {}
    }
#endif

    func testScrollToBoundsDoesNotPrintDebugOutput() {
        let player = IRPlayerImp.player()

        let output = captureStandardOutput {
            player.glViewDidScroll(toBounds: nil)
        }

        XCTAssertEqual(output, "")
        withExtendedLifetime(player) {}
    }

    func testReleaseDoesNotPrintDebugOutput() {
        var player: IRPlayerImp? = IRPlayerImp.player()
        XCTAssertNotNil(player)

        let output = captureStandardOutput {
            player = nil
        }

        XCTAssertEqual(output, "")
    }
}

private func postPlayerNotification(_ name: String, object: AnyObject) {
    NotificationCenter.default.post(name: Notification.Name(rawValue: name), object: object)
}

private final class PlayerNotificationRecorder: NSObject {
    private(set) var stateCount = 0
    private(set) var progressCount = 0
    private(set) var playableCount = 0
    private(set) var errorCount = 0

    @objc func didReceiveState(_ notification: Notification) {
        stateCount += 1
    }

    @objc func didReceiveProgress(_ notification: Notification) {
        progressCount += 1
    }

    @objc func didReceivePlayable(_ notification: Notification) {
        playableCount += 1
    }

    @objc func didReceiveError(_ notification: Notification) {
        errorCount += 1
    }
}

private final class PlayerLoggerRecorder: IRPlayerLoggerDelegate {
    private(set) var records: [(message: String, level: IRPlayerLogLevel, category: String)] = []

    func irPlayer(didLog message: String, level: IRPlayerLogLevel, category: String) {
        records.append((message, level, category))
    }
}
