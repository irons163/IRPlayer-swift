import AVFoundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRAVPlayerSemanticsTests: XCTestCase {
    private static let allStates: [IRPlayerState] = [
        .none,
        .buffering,
        .readyToPlay,
        .playing,
        .suspend,
        .finished,
        .failed
    ]

    func testTrackNameFallsBackForMissingOrBlankLanguage() {
        XCTAssertEqual(
            IRAVPlayer.trackName(
                languageCode: nil,
                trackID: 7
            ),
            "Track 7"
        )
        XCTAssertEqual(
            IRAVPlayer.trackName(
                languageCode: "",
                trackID: 8
            ),
            "Track 8"
        )
        XCTAssertEqual(
            IRAVPlayer.trackName(
                languageCode: " \n ",
                trackID: 9
            ),
            "Track 9"
        )
        XCTAssertEqual(
            IRAVPlayer.trackName(
                languageCode: "en",
                trackID: 10
            ),
            "en"
        )
    }

    func testMediaSelectionTrackIDAcceptsExactIntegers() {
        let key = IRAVPlayer.avMediaSelectionOptionTrackIDKey

        XCTAssertEqual(
            IRAVPlayer.mediaSelectionTrackID(
                from: [key: 42]
            ),
            42
        )
        XCTAssertEqual(
            IRAVPlayer.mediaSelectionTrackID(
                from: [key: NSNumber(value: 43)]
            ),
            43
        )
        XCTAssertEqual(
            IRAVPlayer.mediaSelectionTrackID(
                from: [key: NSNumber(value: Int.min)]
            ),
            Int.min
        )
        XCTAssertEqual(
            IRAVPlayer.mediaSelectionTrackID(
                from: [key: NSNumber(value: Int.max)]
            ),
            Int.max
        )
    }

    func testMediaSelectionTrackIDRejectsInvalidContainersAndTypes() {
        let key = IRAVPlayer.avMediaSelectionOptionTrackIDKey

        XCTAssertNil(
            IRAVPlayer.mediaSelectionTrackID(
                from: [key: "44"]
            )
        )
        XCTAssertNil(
            IRAVPlayer.mediaSelectionTrackID(
                from: [:] as [String: Any]
            )
        )
        XCTAssertNil(
            IRAVPlayer.mediaSelectionTrackID(
                from: "not-a-dictionary"
            )
        )
        XCTAssertNil(
            IRAVPlayer.mediaSelectionTrackID(from: nil)
        )
    }

    func testMediaSelectionTrackIDRejectsMalformedNumbers() {
        let key = IRAVPlayer.avMediaSelectionOptionTrackIDKey

        XCTAssertNil(
            IRAVPlayer.mediaSelectionTrackID(
                from: [key: NSNumber(value: true)]
            )
        )
        XCTAssertNil(
            IRAVPlayer.mediaSelectionTrackID(
                from: [key: NSNumber(value: 1.5)]
            )
        )
        XCTAssertNil(
            IRAVPlayer.mediaSelectionTrackID(
                from: [key: NSNumber(value: UInt64.max)]
            )
        )
    }

    func testDefaultTrackSelectsExactIDAndFallsBackToFirst() {
        let first = makeTrack(index: 1)
        let second = makeTrack(index: 2)
        let key = IRAVPlayer.avMediaSelectionOptionTrackIDKey

        XCTAssertTrue(
            IRAVPlayer.defaultTrack(
                from: [first, second],
                propertyList: [key: 2]
            ) === second
        )
        XCTAssertTrue(
            IRAVPlayer.defaultTrack(
                from: [first, second],
                propertyList: [key: "2"]
            ) === first
        )
        XCTAssertTrue(
            IRAVPlayer.defaultTrack(
                from: [first, second],
                propertyList: nil
            ) === first
        )
        XCTAssertNil(
            IRAVPlayer.defaultTrack(
                from: [],
                propertyList: [key: 2]
            )
        )
    }

    func testSeekTimeConvertsFiniteNonNegativeSeconds() throws {
        let zero = try XCTUnwrap(
            IRAVPlayer.seekTime(for: 0)
        )
        let fractional = try XCTUnwrap(
            IRAVPlayer.seekTime(for: 1.25)
        )

        XCTAssertTrue(zero.isValid)
        XCTAssertEqual(CMTimeGetSeconds(zero), 0)
        XCTAssertTrue(fractional.isValid)
        XCTAssertEqual(
            CMTimeGetSeconds(fractional),
            1.25,
            accuracy: 0.0001
        )
    }

    func testSeekTimeRejectsNegativeNonFiniteAndOverflowingSeconds() {
        XCTAssertNil(IRAVPlayer.seekTime(for: -0.1))
        XCTAssertNil(IRAVPlayer.seekTime(for: .nan))
        XCTAssertNil(IRAVPlayer.seekTime(for: .infinity))
        XCTAssertNil(
            IRAVPlayer.seekTime(
                for: TimeInterval.greatestFiniteMagnitude
            )
        )
    }

    func testFiniteSecondsReturnsFinitePositiveAndNegativeValues() {
        XCTAssertEqual(
            IRAVPlayer.finiteSeconds(
                from: CMTimeMakeWithSeconds(
                    2.5,
                    preferredTimescale: 1_000
                )
            ),
            2.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRAVPlayer.finiteSeconds(
                from: CMTimeMakeWithSeconds(
                    -1.25,
                    preferredTimescale: 1_000
                )
            ),
            -1.25,
            accuracy: 0.0001
        )
    }

    func testFiniteSecondsDefaultsInvalidTimesToZero() {
        XCTAssertEqual(
            IRAVPlayer.finiteSeconds(from: .invalid),
            0
        )
        XCTAssertEqual(
            IRAVPlayer.finiteSeconds(from: .indefinite),
            0
        )
        XCTAssertEqual(
            IRAVPlayer.finiteSeconds(
                from: CMTime(value: 1, timescale: 0)
            ),
            0
        )
    }

    func testPlayableEndTimeClampsFiniteRanges() {
        XCTAssertEqual(
            IRAVPlayer.playableEndTime(
                start: 2,
                duration: 3,
                totalDuration: 10
            ),
            5
        )
        XCTAssertEqual(
            IRAVPlayer.playableEndTime(
                start: 8,
                duration: 5,
                totalDuration: 10
            ),
            10
        )
        XCTAssertEqual(
            IRAVPlayer.playableEndTime(
                start: -2,
                duration: 1,
                totalDuration: 10
            ),
            0
        )
    }

    func testPlayableEndTimeRejectsOverflowAndInvalidDuration() {
        XCTAssertEqual(
            IRAVPlayer.playableEndTime(
                start: .greatestFiniteMagnitude,
                duration: .greatestFiniteMagnitude,
                totalDuration: 10
            ),
            0
        )
        XCTAssertEqual(
            IRAVPlayer.playableEndTime(
                start: 1,
                duration: .nan,
                totalDuration: 10
            ),
            0
        )
        XCTAssertEqual(
            IRAVPlayer.playableEndTime(
                start: 1,
                duration: 2,
                totalDuration: .nan
            ),
            0
        )
    }

    func testUnknownAndFailedItemStatusesIgnoreCurrentState() {
        for state in Self.allStates {
            XCTAssertEqual(
                IRAVPlayer.itemStatusDecision(
                    status: .unknown,
                    currentState: state
                ),
                .buffer,
                "unknown status from \(state)"
            )
            XCTAssertEqual(
                IRAVPlayer.itemStatusDecision(
                    status: .failed,
                    currentState: state
                ),
                .fail,
                "failed status from \(state)"
            )
        }
    }

    func testReadyItemStatusCoversEveryCurrentState() {
        let cases: [
            (IRPlayerState, IRAVPlayer.ItemStatusDecision)
        ] = [
            (.none, .markReady),
            (.buffering, .playIfNeeded),
            (.readyToPlay, .markReady),
            (.playing, .playIfNeeded),
            (.suspend, .ignore),
            (.finished, .ignore),
            (.failed, .ignore)
        ]

        for (state, expected) in cases {
            XCTAssertEqual(
                IRAVPlayer.itemStatusDecision(
                    status: .readyToPlay,
                    currentState: state
                ),
                expected,
                "ready status from \(state)"
            )
        }
    }

    func testPlayTransitionCoversEveryPlayerState() {
        let cases: [(IRPlayerState, IRPlayerState?)] = [
            (.none, .buffering),
            (.buffering, nil),
            (.readyToPlay, .playing),
            (.playing, nil),
            (.suspend, .playing),
            (.finished, nil),
            (.failed, nil)
        ]

        for (state, expected) in cases {
            XCTAssertEqual(
                IRAVPlayer.nextStateAfterPlay(from: state),
                expected,
                "play transition from \(state)"
            )
        }
    }

    func testPauseTransitionCoversEveryPlayerState() {
        for state in Self.allStates {
            XCTAssertEqual(
                IRAVPlayer.nextStateAfterPause(from: state),
                state == .failed ? nil : .suspend,
                "pause transition from \(state)"
            )
        }
    }

    func testRetryClassificationCoversEveryPlayerState() {
        let retryStates: Set<IRPlayerState> = [
            .buffering,
            .readyToPlay,
            .playing
        ]

        for state in Self.allStates {
            XCTAssertEqual(
                IRAVPlayer.shouldRetryPlayAfterDelay(
                    for: state
                ),
                retryStates.contains(state),
                "retry classification for \(state)"
            )
        }
    }

    func testActiveClassificationCoversEveryPlayerState() {
        let activeStates: Set<IRPlayerState> = [
            .buffering,
            .playing
        ]

        for state in Self.allStates {
            XCTAssertEqual(
                IRAVPlayer.isActivePlaybackState(state),
                activeStates.contains(state),
                "active classification for \(state)"
            )
        }
    }

    func testAssetLoadDecisionFailsWhenAnyRequiredKeyFails() {
        XCTAssertEqual(
            IRAVPlayer.avAssetLoadDecision(
                keyStatuses: [.loaded, .failed],
                trackStatus: .loaded
            ),
            .fail
        )
    }

    func testAssetLoadDecisionSetsUpOutputForLoadedTracks() {
        XCTAssertEqual(
            IRAVPlayer.avAssetLoadDecision(
                keyStatuses: [.loaded, .loaded],
                trackStatus: .loaded
            ),
            .setupOutput
        )
    }

    func testAssetLoadDecisionIgnoresIncompleteTracks() {
        XCTAssertEqual(
            IRAVPlayer.avAssetLoadDecision(
                keyStatuses: [.loaded, .loaded],
                trackStatus: .loading
            ),
            .ignore
        )
        XCTAssertEqual(
            IRAVPlayer.avAssetLoadDecision(
                keyStatuses: [.loaded, .loaded],
                trackStatus: nil
            ),
            .ignore
        )
    }

    func testRedirectRequestAppliesHeadersAndPreservesPayload()
        throws
    {
        var request = URLRequest(
            url: URL(
                string:
                    "https://example.com/video.m3u8"
            )!
        )
        request.httpMethod = "POST"
        request.httpBody = Data("payload".utf8)

        let redirectRequest = try XCTUnwrap(
            IRAVPlayer.resourceLoaderRedirectRequest(
                for: request,
                headers: [
                    "Authorization": "Bearer token",
                    "X-Playback-Session": "abc"
                ]
            )
        )

        XCTAssertEqual(redirectRequest.url, request.url)
        XCTAssertEqual(
            redirectRequest.httpMethod,
            request.httpMethod
        )
        XCTAssertEqual(
            redirectRequest.httpBody,
            request.httpBody
        )
        XCTAssertEqual(
            redirectRequest.value(
                forHTTPHeaderField: "Authorization"
            ),
            "Bearer token"
        )
        XCTAssertEqual(
            redirectRequest.value(
                forHTTPHeaderField: "X-Playback-Session"
            ),
            "abc"
        )
    }

    func testRedirectRequestRejectsMissingHeaders() {
        let request = httpsRequest()

        XCTAssertNil(
            IRAVPlayer.resourceLoaderRedirectRequest(
                for: request,
                headers: nil
            )
        )
        XCTAssertNil(
            IRAVPlayer.resourceLoaderRedirectRequest(
                for: request,
                headers: [:]
            )
        )
    }

    func testRedirectRequestRejectsNonHTTPSURL() {
        let request = URLRequest(
            url: URL(
                string:
                    "http://example.com/video.m3u8"
            )!
        )

        XCTAssertNil(
            IRAVPlayer.resourceLoaderRedirectRequest(
                for: request,
                headers: [
                    "Authorization": "Bearer token"
                ]
            )
        )
    }

    func testPlaybackErrorInfoFallsBackWithoutErrors() {
        let errorInfo = IRAVPlayer.playbackErrorInfo(
            playerItem: nil,
            player: nil
        )

        XCTAssertEqual(
            errorInfo.error.domain,
            "AVPlayer playback error"
        )
        XCTAssertEqual(errorInfo.error.code, -1)
        XCTAssertNil(errorInfo.extendedLogData)
        XCTAssertNil(errorInfo.errorEvents)
    }

    func testItemErrorWinsAndCopiesEveryLogField() throws {
        let itemError = NSError(domain: "item", code: 11)
        let playerError = NSError(domain: "player", code: 22)
        let date = Date(timeIntervalSince1970: 77)
        let logData = Data("log".utf8)

        let errorInfo = IRAVPlayer.errorInfo(
            playerItemError: itemError,
            playerError: playerError,
            extendedLogData: logData,
            extendedLogDataStringEncoding:
                String.Encoding.utf16.rawValue,
            errorEvents: [
                .init(
                    date: date,
                    URI:
                        "https://example.com/error.ts",
                    serverAddress: "203.0.113.8",
                    playbackSessionID: "session-77",
                    errorStatusCode: 404,
                    errorDomain: "cdn",
                    errorComment: "missing"
                )
            ]
        )

        XCTAssertEqual(errorInfo.error.domain, "item")
        XCTAssertEqual(errorInfo.error.code, 11)
        XCTAssertEqual(
            errorInfo.extendedLogData,
            logData
        )
        XCTAssertEqual(
            errorInfo.extendedLogDataStringEncoding,
            String.Encoding.utf16.rawValue
        )
        let event = try XCTUnwrap(
            errorInfo.errorEvents?.first
        )
        XCTAssertEqual(event.date, date)
        XCTAssertEqual(
            event.URI,
            "https://example.com/error.ts"
        )
        XCTAssertEqual(
            event.serverAddress,
            "203.0.113.8"
        )
        XCTAssertEqual(
            event.playbackSessionID,
            "session-77"
        )
        XCTAssertEqual(event.errorStatusCode, 404)
        XCTAssertEqual(event.errorDomain, "cdn")
        XCTAssertEqual(event.errorComment, "missing")
    }

    func testPlayerErrorDoesNotReceiveItemLogPayloads() {
        let errorInfo = IRAVPlayer.errorInfo(
            playerItemError: nil,
            playerError:
                NSError(domain: "player", code: 22),
            extendedLogData: Data("ignored".utf8),
            extendedLogDataStringEncoding:
                String.Encoding.utf16.rawValue,
            errorEvents: [
                .init(
                    date: nil,
                    URI: "ignored",
                    serverAddress: "ignored",
                    playbackSessionID: "ignored",
                    errorStatusCode: 500,
                    errorDomain: "ignored",
                    errorComment: "ignored"
                )
            ]
        )

        XCTAssertEqual(errorInfo.error.domain, "player")
        XCTAssertEqual(errorInfo.error.code, 22)
        XCTAssertNil(errorInfo.extendedLogData)
        XCTAssertNil(errorInfo.errorEvents)
    }

    func testErrorEventCopiesOptionalAndRequiredFields() {
        let date = Date(timeIntervalSince1970: 42)

        let event = IRAVPlayer.errorEvent(
            date: date,
            URI:
                "https://example.com/segment.ts",
            serverAddress: "198.51.100.10",
            playbackSessionID: "session-1",
            errorStatusCode: 503,
            errorDomain: "cdn",
            errorComment: "unavailable"
        )

        XCTAssertEqual(event.date, date)
        XCTAssertEqual(
            event.URI,
            "https://example.com/segment.ts"
        )
        XCTAssertEqual(
            event.serverAddress,
            "198.51.100.10"
        )
        XCTAssertEqual(
            event.playbackSessionID,
            "session-1"
        )
        XCTAssertEqual(event.errorStatusCode, 503)
        XCTAssertEqual(event.errorDomain, "cdn")
        XCTAssertEqual(
            event.errorComment,
            "unavailable"
        )
    }

    func testExtendedLogDataIgnoresEmptyAndCopiesNonEmpty() {
        let errorInfo = IRError()

        IRAVPlayer.applyExtendedLogData(
            Data(),
            stringEncoding:
                String.Encoding.utf16.rawValue,
            to: errorInfo
        )
        XCTAssertNil(errorInfo.extendedLogData)
        XCTAssertEqual(
            errorInfo.extendedLogDataStringEncoding,
            String.Encoding.utf8.rawValue
        )

        let logData = Data([1, 2, 3])
        IRAVPlayer.applyExtendedLogData(
            logData,
            stringEncoding:
                String.Encoding.utf16.rawValue,
            to: errorInfo
        )
        XCTAssertEqual(
            errorInfo.extendedLogData,
            logData
        )
        XCTAssertEqual(
            errorInfo.extendedLogDataStringEncoding,
            String.Encoding.utf16.rawValue
        )
    }

    func testItemErrorWithEmptyEventListPublishesEmptyEvents() {
        let errorInfo = IRAVPlayer.errorInfo(
            playerItemError:
                NSError(domain: "item", code: 1),
            playerError: nil,
            extendedLogData: nil,
            extendedLogDataStringEncoding:
                String.Encoding.utf8.rawValue,
            errorEvents: []
        )

        XCTAssertEqual(errorInfo.errorEvents?.count, 0)
    }

    private func makeTrack(index: Int) -> IRPlayerTrack {
        let track = IRPlayerTrack()
        track.index = index
        return track
    }

    private func httpsRequest() -> URLRequest {
        URLRequest(
            url: URL(
                string:
                    "https://example.com/video.m3u8"
            )!
        )
    }
}
