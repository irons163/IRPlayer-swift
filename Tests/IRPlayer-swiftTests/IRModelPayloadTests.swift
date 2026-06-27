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

    func testNotificationPayloadWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRPlayerNotificationPayload.state(previous: .buffering, current: .playing) as NSDictionary,
            IRPlayerNotificationPayloadPolicy.state(previous: .buffering, current: .playing) as NSDictionary
        )
        XCTAssertEqual(
            IRPlayerNotificationPayload.progress(
                percent: NSNumber(value: 0.25),
                current: NSNumber(value: 3),
                total: NSNumber(value: 12)
            ) as NSDictionary,
            IRPlayerNotificationPayloadPolicy.progress(
                percent: NSNumber(value: 0.25),
                current: NSNumber(value: 3),
                total: NSNumber(value: 12)
            ) as NSDictionary
        )
        XCTAssertEqual(
            IRPlayerNotificationPayload.playable(
                percent: NSNumber(value: 0.5),
                current: NSNumber(value: 6),
                total: NSNumber(value: 12)
            ) as NSDictionary,
            IRPlayerNotificationPayloadPolicy.playable(
                percent: NSNumber(value: 0.5),
                current: NSNumber(value: 6),
                total: NSNumber(value: 12)
            ) as NSDictionary
        )
        XCTAssertEqual(
            IRPlayerNotificationPayload.timePercent(current: 3, total: 12),
            IRPlayerNotificationPayloadPolicy.timePercent(current: 3, total: 12)
        )
        XCTAssertEqual(
            IRPlayerNotificationPayload.cgFloat(NSNumber(value: 4.5)),
            IRPlayerNotificationPayloadPolicy.cgFloat(NSNumber(value: 4.5))
        )
        XCTAssertEqual(
            IRPlayerNotificationPayload.state(NSNumber(value: IRPlayerState.failed.rawValue)),
            IRPlayerNotificationPayloadPolicy.state(NSNumber(value: IRPlayerState.failed.rawValue))
        )

        let error = IRError()
        XCTAssertTrue(IRPlayerNotificationPayload.error(error)[IRPlayerErrorKey] as? IRError === error)
        XCTAssertTrue(IRPlayerNotificationPayloadPolicy.error(error)[IRPlayerErrorKey] as? IRError === error)
    }

    func testDefaultIRErrorUsesValidNSError() {
        let error = IRError()

        XCTAssertEqual(error.error.domain, "IRPlayer error")
        XCTAssertEqual(error.error.code, -1)
    }

    func testDefaultIRErrorEventUsesEmptyStatusFields() {
        let event = IRErrorEvent()

        XCTAssertEqual(event.errorStatusCode, 0)
        XCTAssertEqual(event.errorDomain, "")
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

    func testStateParserDefaultsMalformedNumericPayloads() {
        let state = IRModel.state(fromUserInfo: [
            IRPlayerStatePreviousKey: NSNumber(value: 1.5),
            IRPlayerStateCurrentKey: NSNumber(value: true)
        ])

        XCTAssertEqual(state.previous, .none)
        XCTAssertEqual(state.current, .none)
    }

    func testStatePayloadDefaultsOutOfRangeRawValues() {
        XCTAssertEqual(IRPlayerNotificationPayload.state(NSNumber(value: Int.max)), .none)
        XCTAssertEqual(IRPlayerNotificationPayload.state(Int.min), .none)
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

    func testTimeParsersDefaultMalformedBooleanPayloads() {
        let progress = IRModel.progress(fromUserInfo: [
            IRPlayerProgressPercentKey: NSNumber(value: true),
            IRPlayerProgressCurrentKey: NSNumber(value: false),
            IRPlayerProgressTotalKey: true
        ])
        let playable = IRModel.playable(fromUserInfo: [
            IRPlayerPlayablePercentKey: NSNumber(value: true),
            IRPlayerPlayableCurrentKey: NSNumber(value: false),
            IRPlayerPlayableTotalKey: true
        ])

        XCTAssertEqual(progress.percent, 0)
        XCTAssertEqual(progress.current, 0)
        XCTAssertEqual(progress.total, 0)
        XCTAssertEqual(playable.percent, 0)
        XCTAssertEqual(playable.current, 0)
        XCTAssertEqual(playable.total, 0)
    }

    func testCGFloatPayloadConvertsNumericInputsAndDefaultsInvalidValues() {
        XCTAssertEqual(IRPlayerNotificationPayload.cgFloat(CGFloat(2.5)), 2.5, accuracy: 0.0001)
        XCTAssertEqual(IRPlayerNotificationPayload.cgFloat(NSNumber(value: 4.5)), 4.5, accuracy: 0.0001)
        XCTAssertEqual(IRPlayerNotificationPayload.cgFloat(Double(6.5)), 6.5, accuracy: 0.0001)
        XCTAssertEqual(IRPlayerNotificationPayload.cgFloat(Float(8.5)), 8.5, accuracy: 0.0001)
        XCTAssertEqual(IRPlayerNotificationPayload.cgFloat(10), 10, accuracy: 0.0001)
        XCTAssertEqual(IRPlayerNotificationPayload.cgFloat("not-a-number"), 0)
        XCTAssertEqual(IRPlayerNotificationPayload.cgFloat(Double.infinity), 0)
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

    func testTimePayloadsDefaultMalformedBooleanNumbers() {
        let progressPayload = IRPlayerNotificationPayload.progress(
            percent: NSNumber(value: true),
            current: NSNumber(value: false),
            total: NSNumber(value: true)
        )
        let playablePayload = IRPlayerNotificationPayload.playable(
            percent: NSNumber(value: true),
            current: NSNumber(value: false),
            total: NSNumber(value: true)
        )

        XCTAssertEqual(progressPayload[IRPlayerProgressPercentKey] as? NSNumber, NSNumber(value: 0))
        XCTAssertEqual(progressPayload[IRPlayerProgressCurrentKey] as? NSNumber, NSNumber(value: 0))
        XCTAssertEqual(progressPayload[IRPlayerProgressTotalKey] as? NSNumber, NSNumber(value: 0))
        XCTAssertEqual(playablePayload[IRPlayerPlayablePercentKey] as? NSNumber, NSNumber(value: 0))
        XCTAssertEqual(playablePayload[IRPlayerPlayableCurrentKey] as? NSNumber, NSNumber(value: 0))
        XCTAssertEqual(playablePayload[IRPlayerPlayableTotalKey] as? NSNumber, NSNumber(value: 0))
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

    func testErrorParserDefaultsMalformedPayloads() {
        let error = IRModel.error(fromUserInfo: [IRPlayerErrorKey: "not-an-error"])

        XCTAssertEqual(error.error.domain, "IRPlayer error")
        XCTAssertEqual(error.error.code, -1)
    }
}
