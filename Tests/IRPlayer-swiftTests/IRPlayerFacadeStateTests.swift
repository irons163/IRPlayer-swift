import UIKit
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRPlayerFacadeStateTests: XCTestCase {
    func testSettingsStoreNormalizesBoundaryValues() {
        let store = IRPlayerSettingsStore(
            playableBufferInterval: -.infinity,
            volume: .nan
        )

        XCTAssertEqual(store.playableBufferInterval, 2)
        XCTAssertEqual(store.volume, 1)

        store.playableBufferInterval = -4
        store.volume = 2
        XCTAssertEqual(store.playableBufferInterval, 0)
        XCTAssertEqual(store.volume, 1)

        store.volume = -1
        XCTAssertEqual(store.volume, 0)
    }

    func testSettingsSnapshotIsCoherentWithStoredValues() {
        let store = IRPlayerSettingsStore()
        let error = IRError()

        store.decoder = IRPlayerDecoder.AVPlayerDecoder()
        XCTAssertTrue(store.setVideoType(.fisheye))
        XCTAssertFalse(store.setVideoType(.fisheye))
        XCTAssertTrue(store.setDisplayMode(.box))
        XCTAssertFalse(store.setDisplayMode(.box))
        store.autoplay = true
        store.isLiveStream = true
        store.playableBufferInterval = 6
        store.volume = 0.25
        store.viewAnimationHidden = false
        store.error = error

        let snapshot = store.snapshot
        XCTAssertEqual(snapshot.videoType, .fisheye)
        XCTAssertEqual(snapshot.displayMode, .box)
        XCTAssertTrue(snapshot.autoplay)
        XCTAssertTrue(snapshot.isLiveStream)
        XCTAssertEqual(snapshot.playableBufferInterval, 6)
        XCTAssertEqual(snapshot.volume, 0.25)
        XCTAssertFalse(snapshot.viewAnimationHidden)
        XCTAssertTrue(snapshot.error === error)
    }

    func testSettingsStoreSupportsConcurrentMutationAndSnapshots() {
        let store = IRPlayerSettingsStore()

        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            store.volume = CGFloat(index % 3) - 1
            store.playableBufferInterval = TimeInterval(index % 5) - 2
            store.autoplay = index.isMultiple(of: 2)
            _ = store.snapshot
        }

        XCTAssertTrue((0...1).contains(store.volume))
        XCTAssertGreaterThanOrEqual(store.playableBufferInterval, 0)
    }

    func testMediaReplacementDetachesPreviousInputAndBindsCurrentInput() {
        let session = IRPlayerMediaSession()
        let firstOutput = FacadeStateVideoOutputProbe()
        let firstInput = IRFFVideoInput(videoOutput: firstOutput)
        let secondInput = IRFFVideoInput()
        let secondOutput = FacadeStateVideoOutputProbe()
        let firstSource = IRMediaSource(
            url: URL(string: "https://example.com/first.mp4"),
            headers: ["A": "1"],
            videoInput: firstInput
        )
        let secondSource = IRMediaSource(
            url: URL(string: "https://example.com/second.mp4"),
            headers: ["B": "2"],
            videoInput: secondInput
        )

        let first = session.replace(with: firstSource)
        XCTAssertNil(first.previousVideoInput)
        XCTAssertTrue(first.currentVideoInput === firstInput)
        XCTAssertTrue(firstInput.videoOutput === firstOutput)

        let second = session.replace(with: secondSource)
        XCTAssertTrue(second.previousVideoInput === firstInput)
        XCTAssertTrue(second.currentVideoInput === secondInput)
        XCTAssertNil(firstInput.videoOutput)

        session.bindCurrentVideoInput(to: secondOutput)
        XCTAssertTrue(secondInput.videoOutput === secondOutput)
        XCTAssertEqual(session.snapshot.contentHeaders, ["B": "2"])
    }

    func testClearingMediaSessionReturnsAndDetachesOwnedInput() {
        let session = IRPlayerMediaSession()
        let output = FacadeStateVideoOutputProbe()
        let input = IRFFVideoInput(videoOutput: output)
        session.replace(
            with: IRMediaSource(
                url: URL(string: "https://example.com/video.mp4"),
                videoInput: input
            )
        )

        let released = session.clear()

        XCTAssertTrue(released === input)
        XCTAssertNil(input.videoOutput)
        XCTAssertNil(session.snapshot.source)
        XCTAssertNil(session.snapshot.contentURL)
        XCTAssertNil(session.snapshot.contentHeaders)
        XCTAssertNil(session.snapshot.videoInput)
    }

    func testLegacyHeadersNormalizeEmptyDictionaries() {
        let session = IRPlayerMediaSession()

        session.setLegacyHeaders(["Authorization": "token"])
        XCTAssertEqual(
            session.snapshot.contentHeaders,
            ["Authorization": "token"]
        )

        session.setLegacyHeaders([:])
        XCTAssertNil(session.snapshot.contentHeaders)
        session.setLegacyHeaders(nil)
        XCTAssertNil(session.snapshot.contentHeaders)
    }

    func testLegacyHeadersKeepInstalledSourceCoherent() {
        let session = IRPlayerMediaSession()
        session.replace(
            with: IRMediaSource(
                url: URL(
                    string: "https://example.com/video.mp4"
                ),
                headers: ["Initial": "value"]
            )
        )

        session.setLegacyHeaders(
            ["Authorization": "token"]
        )

        XCTAssertEqual(
            session.snapshot.contentHeaders,
            ["Authorization": "token"]
        )
        XCTAssertEqual(
            session.snapshot.source?.headers,
            ["Authorization": "token"]
        )

        session.setLegacyHeaders(nil)
        XCTAssertNil(session.snapshot.contentHeaders)
        XCTAssertEqual(session.snapshot.source?.headers, [:])
    }

    func testConcurrentMediaReplacementEndsWithOneBoundCurrentInput() {
        let session = IRPlayerMediaSession()
        let inputs = (0..<100).map { _ in IRFFVideoInput() }
        let output = FacadeStateVideoOutputProbe()

        DispatchQueue.concurrentPerform(iterations: inputs.count) { index in
            session.replace(
                with: IRMediaSource(
                    url: URL(
                        string: "https://example.com/\(index).mp4"
                    ),
                    videoInput: inputs[index]
                )
            )
            session.bindCurrentVideoInput(to: output)
        }

        let current = session.snapshot.videoInput
        XCTAssertNotNil(current)
        XCTAssertTrue(current?.videoOutput === output)
        XCTAssertEqual(
            inputs.filter { $0.videoOutput != nil }.count,
            1
        )
    }
}

private final class FacadeStateVideoOutputProbe:
    NSObject,
    IRFFDecoderVideoOutput
{}
