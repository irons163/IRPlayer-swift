//
//  IRPlayer_swiftTests.swift
//  IRPlayer-swiftTests
//
//  Created by Phil Chang on 2022/4/11.
//  Copyright © 2022 Phil. All rights reserved.
//

import AVFoundation
import CoreGraphics
import simd
import XCTest
@testable import IRPlayer_swift

final class IRPlayerDecoderTests: XCTestCase {

    func testVideoFormatResolverClassifiesNilAsError() {
        XCTAssertEqual(IRVideoFormatResolver.format(for: nil), .error)
    }

    func testVideoFormatResolverClassifiesSchemesAndExtensionsCaseInsensitively() {
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "RTMP://example.com/live")), .rtmp)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "rtsp://example.com/live")), .rtsp)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "https://example.com/movie.MP4?token=1")), .mpeg4)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "https://example.com/live.M3U8")), .m3u8)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(fileURLWithPath: "/tmp/clip.flv")), .flv)
    }

    func testDecoderTypeUsesConfiguredPolicyForResolvedFormat() {
        let decoder = IRPlayerDecoder.FFmpegDecoder()
        decoder.mpeg4Format = .avPlayer

        XCTAssertEqual(decoder.decoderTypeForContentURL(contentURL: NSURL(string: "https://example.com/video.mp4")), .avPlayer)
        XCTAssertEqual(decoder.decoderTypeForContentURL(contentURL: NSURL(string: "https://example.com/video.unknown")), .ffmpeg)
        XCTAssertEqual(decoder.decoderTypeForContentURL(contentURL: nil), .error)
    }
}

final class IRModelPayloadTests: XCTestCase {

    func testDefaultIRErrorUsesValidNSError() {
        let error = IRError()

        XCTAssertEqual(error.error.domain, "IRPlayer error")
        XCTAssertEqual(error.error.code, -1)
    }

    func testStatePayloadRoundTripsThroughModelParser() {
        let payload = IRPlayerNotificationPayload.state(previous: .buffering, current: .playing)
        let state = IRModel.state(fromUserInfo: payload)

        XCTAssertEqual(state.previous, .buffering)
        XCTAssertEqual(state.current, .playing)
    }

    func testStateParserAcceptsRawNumericPayloads() {
        let state = IRModel.state(fromUserInfo: [
            IRPlayerStatePreviousKey: NSNumber(value: IRPlayerState.readyToPlay.rawValue),
            IRPlayerStateCurrentKey: IRPlayerState.failed.rawValue
        ])

        XCTAssertEqual(state.previous, .readyToPlay)
        XCTAssertEqual(state.current, .failed)
    }

    func testProgressParserAcceptsNumericPayloadsAndDefaultsMissingValues() {
        let progress = IRModel.progress(fromUserInfo: [
            IRPlayerProgressPercentKey: NSNumber(value: 0.5),
            IRPlayerProgressCurrentKey: 3,
            IRPlayerProgressTotalKey: Double(6)
        ])

        XCTAssertEqual(progress.percent, 0.5, accuracy: 0.0001)
        XCTAssertEqual(progress.current, 3, accuracy: 0.0001)
        XCTAssertEqual(progress.total, 6, accuracy: 0.0001)

        let emptyProgress = IRModel.progress(fromUserInfo: [:])
        XCTAssertEqual(emptyProgress.percent, 0)
        XCTAssertEqual(emptyProgress.current, 0)
        XCTAssertEqual(emptyProgress.total, 0)
    }

    func testPlayablePayloadUsesZeroDefaultsForNilValues() {
        let payload = IRPlayerNotificationPayload.playable(percent: nil, current: NSNumber(value: 4), total: nil)
        let playable = IRModel.playable(fromUserInfo: payload)

        XCTAssertEqual(playable.percent, 0)
        XCTAssertEqual(playable.current, 4, accuracy: 0.0001)
        XCTAssertEqual(playable.total, 0)
    }

    func testErrorParserReturnsExistingIRErrorAndWrapsNSError() {
        let existingError = IRError()
        existingError.error = NSError(domain: "existing", code: 7)
        XCTAssertTrue(IRModel.error(fromUserInfo: IRPlayerNotificationPayload.error(existingError)) === existingError)

        let nsError = NSError(domain: "wrapped", code: 8)
        let wrappedError = IRModel.error(fromUserInfo: [IRPlayerErrorKey: nsError])
        XCTAssertEqual(wrappedError.error.domain, "wrapped")
        XCTAssertEqual(wrappedError.error.code, 8)
    }
}

final class IRPlayerNotificationTests: XCTestCase {

    func testPostNotificationPostsAsynchronouslyOnMainQueue() {
        let name = Notification.Name("IRPlayerNotificationTests.\(UUID().uuidString)")
        let expectation = expectation(description: "notification posted")
        let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(notification.userInfo?[IRPlayerProgressCurrentKey] as? NSNumber, NSNumber(value: 2))
            expectation.fulfill()
        }

        IRPlayerNotification.postNotification(name: name.rawValue, object: nil, userInfo: [
            IRPlayerProgressCurrentKey: NSNumber(value: 2)
        ])

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}

final class IRAVPlayerTests: XCTestCase {

    func testSetupAVPlayerItemIgnoresMissingAsset() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avAsset = nil
        avPlayer.setupAVPlayerItem(autoLoadedAsset: false)

        XCTAssertNil(avPlayer.avPlayerItem)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayer = nil
        avPlayer.play()

        XCTAssertEqual(avPlayer.state, .none)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPauseIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayer = nil
        avPlayer.pause()

        XCTAssertEqual(avPlayer.state, .none)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSetPlayIfNeededIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.state = .playing
        avPlayer.avPlayer = nil
        avPlayer.setPlayIfNeeded()

        XCTAssertEqual(avPlayer.state, .playing)
        XCTAssertFalse(avPlayer.needPlay)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSeekIgnoresMissingPlayerItem() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        var completionCalled = false

        avPlayer.avPlayerItem = nil
        avPlayer.seek(to: 1) { _ in
            completionCalled = true
        }

        XCTAssertFalse(avPlayer.seeking)
        XCTAssertFalse(completionCalled)
        withExtendedLifetime(abstractPlayer) {}
    }
}

final class IRFFFrameQueueTests: XCTestCase {

    func testFrameQueueTracksCountDurationAndSizeWhenPuttingAndFetchingFrames() {
        let queue = IRFFFrameQueue.frameQueue()
        let first = makeFrame(position: 0, duration: 0.25, size: 10)
        let second = makeFrame(position: 1, duration: 0.5, size: 20)

        queue.putFrame(first)
        queue.putFrame(second)

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.duration, 0.75, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 30)

        XCTAssertTrue(queue.getFrameAsync() === first)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testPutSortFrameReturnsFramesInAscendingPositionOrder() {
        let queue = IRFFFrameQueue.frameQueue()
        let later = makeFrame(position: 3, duration: 0.1, size: 1)
        let earlier = makeFrame(position: 1, duration: 0.1, size: 1)
        let middle = makeFrame(position: 2, duration: 0.1, size: 1)

        queue.putSortFrame(later)
        queue.putSortFrame(earlier)
        queue.putSortFrame(middle)

        XCTAssertTrue(queue.getFrameAsync() === earlier)
        XCTAssertTrue(queue.getFrameAsync() === middle)
        XCTAssertTrue(queue.getFrameAsync() === later)
    }

    private func makeFrame(position: TimeInterval, duration: TimeInterval, size: Int) -> IRFFFrame {
        let frame = IRFFFrame()
        frame.position = position
        frame.duration = duration
        frame.size = size
        return frame
    }
}

final class IRFFFramePoolTests: XCTestCase {

    func testDefaultPoolsCreateExpectedFrameTypesWithoutModuleNameLookup() {
        let videoFrame = IRFFFramePool.videoPool().getUnuseFrame()
        let audioFrame = IRFFFramePool.audioPool().getUnuseFrame()

        XCTAssertTrue(videoFrame is IRFFAVYUVVideoFrame)
        XCTAssertTrue(audioFrame is IRFFAudioFrame)
    }

    func testFramePoolMovesFramesThroughUsedPlayingAndUnuseBuckets() throws {
        let pool = IRFFFramePool.pool(withCapacity: 2, frameClassName: IRFFFrame.self)
        let frame = try XCTUnwrap(pool.getUnuseFrame())

        XCTAssertEqual(pool.usedCount, 1)
        XCTAssertEqual(pool.unuseCount, 0)

        frame.startPlaying()
        XCTAssertEqual(pool.usedCount, 0)
        XCTAssertEqual(pool.unuseCount, 0)
        XCTAssertTrue(pool.playingFrame === frame)

        frame.stopPlaying()
        XCTAssertNil(pool.playingFrame)
        XCTAssertEqual(pool.usedCount, 0)
        XCTAssertEqual(pool.unuseCount, 1)
    }
}

final class IRGLRenderModeFactoryTests: XCTestCase {

    func testNormalModesContainOnly2DModeWithParameter() {
        let parameter = IRMediaParameter(width: 100, height: 50)
        let modes = IRGLRenderModeFactory.createNormalModes(with: parameter)

        XCTAssertEqual(modes.count, 1)
        XCTAssertTrue(modes[0] is IRGLRenderMode2D)
        XCTAssertTrue(modes[0].parameter === parameter)
    }

    func testFisheyeModesHaveExpectedOrderNamesAndDefaults() {
        let modes = IRGLRenderModeFactory.createFisheyeModes(with: nil)

        XCTAssertEqual(modes.map(\.name), ["Panorama", "Onelen", "Fourlens", "Rawdata"])
        XCTAssertTrue(modes[0] is IRGLRenderMode2DFisheye2Pano)
        XCTAssertTrue(modes[1] is IRGLRenderMode3DFisheye)
        XCTAssertTrue(modes[2] is IRGLRenderModeMulti4P)
        XCTAssertTrue(modes[3] is IRGLRenderMode2D)
        XCTAssertEqual(modes[0].contentMode, .scaleAspectFill)
        XCTAssertEqual(modes[0].wideDegreeX, 360)
        XCTAssertEqual(modes[0].wideDegreeY, 20)
        XCTAssertFalse(modes[3].shiftController.enabled)
    }

    func testPanoramaModeUsesScaleAspectFillAndWideDegrees() {
        let mode = IRGLRenderModeFactory.createPanoramaMode(with: nil)

        XCTAssertTrue(mode is IRGLRenderMode2DFisheye2Pano)
        XCTAssertEqual(mode.contentMode, .scaleAspectFill)
        XCTAssertEqual(mode.wideDegreeX, 360)
        XCTAssertEqual(mode.wideDegreeY, 20)
    }

    func testFisheyeRenderModesIgnoreIncompatibleProgramParameters() {
        let invalidParameter = IRMediaParameter(width: 100, height: 50)

        let fisheyeMode = IRGLRenderMode3DFisheye()
        fisheyeMode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                                     viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 240),
                                     parameter: invalidParameter)

        let fourPanelMode = IRGLRenderModeMulti4P()
        fourPanelMode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                                       viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 240),
                                       parameter: invalidParameter)

        XCTAssertNil(fisheyeMode.program)
        XCTAssertNil(fourPanelMode.program)
    }
}

final class IRGLGestureControllerTests: XCTestCase {

    func testClearingCurrentModeClearsSmoothScrollMode() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let smoothScroll = IRSmoothScrollController(targetView: view)
        let gestureController = IRGLGestureController()

        gestureController.smoothScroll = smoothScroll
        gestureController.currentMode = IRGLRenderMode2D()

        gestureController.currentMode = nil

        XCTAssertNil(smoothScroll.currentMode)
        withExtendedLifetime(smoothScroll) {}
    }
}

final class IRMatrix4Tests: XCTestCase {

    func testTranslationMatrixStoresTranslationInLastColumn() {
        let matrix = IRMatrix4.makeTranslation(1, 2, 3)

        XCTAssertEqual(matrix.columns.3.x, 1, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.y, 2, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.z, 3, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.w, 1, accuracy: 0.0001)
    }

    func testScaleMatrixStoresScaleOnDiagonal() {
        let matrix = IRMatrix4.makeScale(2, 3, 4)

        XCTAssertEqual(matrix.columns.0.x, 2, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.1.y, 3, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.2.z, 4, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.w, 1, accuracy: 0.0001)
    }

    func testMultiplyReturnsSimdProduct() {
        let translation = IRMatrix4.makeTranslation(1, 2, 3)
        let scale = IRMatrix4.makeScale(2, 2, 2)

        XCTAssertEqual(IRMatrix4.multiply(translation, scale), simd_mul(translation, scale))
    }
}

final class IRAudioManagerNotificationTests: XCTestCase {

    func testMalformedAudioSessionNotificationsAreIgnored() {
        let manager = IRAudioManager()
        let target = NSObject()
        var interruptionCalled = false
        var routeChangeCalled = false
        manager.setHandlerTarget(target, interruption: { _, _, _, _ in
            interruptionCalled = true
        }, routeChange: { _, _, _ in
            routeChangeCalled = true
        })

        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [:])
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: [:])

        XCTAssertFalse(interruptionCalled)
        XCTAssertFalse(routeChangeCalled)
    }
}

final class IRAudioManagerRenderTests: XCTestCase {

    func testRenderFramesIgnoresMissingAudioBufferList() {
        let manager = IRAudioManager()

        XCTAssertEqual(manager.renderFrames(16, ioData: nil), noErr)
    }
}
