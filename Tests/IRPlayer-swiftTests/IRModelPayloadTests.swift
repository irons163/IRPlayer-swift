//
//  IRModelPayloadTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Foundation
import XCTest
@testable import IRPlayer_swift

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

    func testProgressParserDefaultsNonFiniteNumericPayloads() {
        let progress = IRModel.progress(fromUserInfo: [
            IRPlayerProgressPercentKey: NSNumber(value: Double.nan),
            IRPlayerProgressCurrentKey: NSNumber(value: Double.infinity),
            IRPlayerProgressTotalKey: NSNumber(value: -Double.infinity)
        ])

        XCTAssertEqual(progress.percent, 0)
        XCTAssertEqual(progress.current, 0)
        XCTAssertEqual(progress.total, 0)
    }

    func testProgressPayloadDefaultsNonFiniteNumbers() {
        let payload = IRPlayerNotificationPayload.progress(
            percent: NSNumber(value: Double.nan),
            current: NSNumber(value: Double.infinity),
            total: NSNumber(value: -Double.infinity)
        )
        let progress = IRModel.progress(fromUserInfo: payload)

        XCTAssertEqual(progress.percent, 0)
        XCTAssertEqual(progress.current, 0)
        XCTAssertEqual(progress.total, 0)
    }

    func testTimePercentUsesFinitePositiveTotal() {
        XCTAssertEqual(IRPlayerNotificationPayload.timePercent(current: 3, total: 12), NSNumber(value: 0.25))
        XCTAssertEqual(IRPlayerNotificationPayload.timePercent(current: 3, total: 0), NSNumber(value: 0))
        XCTAssertEqual(IRPlayerNotificationPayload.timePercent(current: 3, total: -1), NSNumber(value: 0))
        XCTAssertEqual(IRPlayerNotificationPayload.timePercent(current: Double.nan, total: 12), NSNumber(value: 0))
        XCTAssertEqual(IRPlayerNotificationPayload.timePercent(current: 3, total: Double.infinity), NSNumber(value: 0))
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
