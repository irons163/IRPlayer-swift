//
//  IRAudioManagerRenderTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import AVFoundation
import XCTest
@testable import IRPlayer_swift

final class IRAudioManagerRenderTests: XCTestCase {

    func testRegisterAudioSessionDoesNotPrintDebugDiagnostics() {
        let manager = IRAudioManager()
        var setupCallCount = 0

        let output = captureStandardOutput {
            let registered = manager.registerAudioSession {
                setupCallCount += 1
                return true
            }

            XCTAssertTrue(registered)
            XCTAssertTrue(manager.registerAudioSession {
                XCTFail("Audio session setup should not be repeated once registered")
                return false
            })
        }

        XCTAssertEqual(setupCallCount, 1)
        XCTAssertFalse(output.contains("IRAudioManager did error"))
        XCTAssertFalse(output.contains("IRAudioManager did warning"))
    }

    func testRequiredAudioGraphRejectsMissingGraph() {
        let result = IRAudioManager.requiredAudioGraph(nil, domain: "missing graph")

        switch result {
        case .success:
            XCTFail("Missing graph should not be accepted")
        case .failure(let error):
            XCTAssertEqual(error.domain, "missing graph")
            XCTAssertEqual(error.code, -1)
        }
    }

    func testRequiredAudioUnitRejectsMissingUnit() {
        let result = IRAudioManager.requiredAudioUnit(nil, domain: "missing audio unit")

        switch result {
        case .success:
            XCTFail("Missing audio unit should not be accepted")
        case .failure(let error):
            XCTAssertEqual(error.domain, "missing audio unit")
            XCTAssertEqual(error.code, -1)
        }
    }

    func testRenderFramesIgnoresMissingAudioBufferList() {
        let manager = IRAudioManager()

        XCTAssertEqual(manager.renderFrames(16, ioData: nil), noErr)
    }

    func testRenderSampleCountRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRAudioManager.renderSampleCount(numberOfFrames: 0, numberOfChannels: 2))
        XCTAssertNil(IRAudioManager.renderSampleCount(numberOfFrames: 10, numberOfChannels: 0))
        XCTAssertNil(IRAudioManager.renderSampleCount(numberOfFrames: .max, numberOfChannels: .max))
    }

    func testRenderSampleCountCalculatesInterleavedSampleTotal() {
        XCTAssertEqual(IRAudioManager.renderSampleCount(numberOfFrames: 10, numberOfChannels: 2), 20)
    }

    func testRenderSampleCountWrapperMatchesPolicy() {
        XCTAssertEqual(
            IRAudioManager.renderSampleCount(numberOfFrames: 10, numberOfChannels: 2),
            IRAudioManagerPolicy.renderSampleCount(numberOfFrames: 10, numberOfChannels: 2)
        )
        XCTAssertNil(IRAudioManagerPolicy.renderSampleCount(numberOfFrames: 0, numberOfChannels: 2))
    }

    func testRequiredAudioResourceWrappersMatchPolicyFailures() {
        switch (IRAudioManager.requiredAudioGraph(nil, domain: "missing graph"),
                IRAudioManagerPolicy.requiredAudioGraph(nil, domain: "missing graph")) {
        case (.failure(let wrapperError), .failure(let policyError)):
            XCTAssertEqual(wrapperError.domain, policyError.domain)
            XCTAssertEqual(wrapperError.code, policyError.code)
        default:
            XCTFail("Missing graph should fail for wrapper and policy")
        }

        switch (IRAudioManager.requiredAudioUnit(nil, domain: "missing audio unit"),
                IRAudioManagerPolicy.requiredAudioUnit(nil, domain: "missing audio unit")) {
        case (.failure(let wrapperError), .failure(let policyError)):
            XCTAssertEqual(wrapperError.domain, policyError.domain)
            XCTAssertEqual(wrapperError.code, policyError.code)
        default:
            XCTFail("Missing audio unit should fail for wrapper and policy")
        }
    }
}
