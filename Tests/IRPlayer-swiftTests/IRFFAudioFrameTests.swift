//
//  IRFFAudioFrameTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRFFAudioFrameTests: XCTestCase {

    func testSampleCapacityRejectsInvalidByteLengths() {
        XCTAssertNil(IRFFAudioFrame.sampleCapacity(forByteLength: 0))
        XCTAssertNil(IRFFAudioFrame.sampleCapacity(forByteLength: -1))
    }

    func testSampleCapacityRoundsUpToFloatStorage() {
        XCTAssertEqual(IRFFAudioFrame.sampleCapacity(forByteLength: MemoryLayout<Float>.size), 1)
        XCTAssertEqual(IRFFAudioFrame.sampleCapacity(forByteLength: MemoryLayout<Float>.size + 1), 2)
    }

    func testShouldAllocateSampleBufferOnlyWhenCapacityIsTooSmall() {
        XCTAssertFalse(IRFFAudioFrame.shouldAllocateSampleBuffer(currentCapacity: 4, requiredCapacity: 4))
        XCTAssertFalse(IRFFAudioFrame.shouldAllocateSampleBuffer(currentCapacity: 5, requiredCapacity: 4))
        XCTAssertTrue(IRFFAudioFrame.shouldAllocateSampleBuffer(currentCapacity: 3, requiredCapacity: 4))
    }
}
