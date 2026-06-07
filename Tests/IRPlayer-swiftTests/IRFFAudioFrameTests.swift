//
//  IRFFAudioFrameTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRFFAudioFrameTests: XCTestCase {

    func testAudioFrameReportsAudioType() {
        XCTAssertEqual(IRFFAudioFrame().type, .audio)
    }

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

    func testSetSamplesLengthAllocatesStorageAndResetsOutputOffset() throws {
        let frame = IRFFAudioFrame()
        frame.outputOffset = 8

        frame.setSamplesLength(MemoryLayout<Float>.size * 2)

        XCTAssertEqual(frame.size, MemoryLayout<Float>.size * 2)
        XCTAssertEqual(frame.outputOffset, 0)
        let samples = try XCTUnwrap(frame.samples)
        samples[0] = 1.25
        samples[1] = -2.5
        XCTAssertEqual(samples[0], 1.25, accuracy: 0.0001)
        XCTAssertEqual(samples[1], -2.5, accuracy: 0.0001)
    }

    func testSetSamplesLengthReusesExistingStorageWhenCapacityIsEnough() throws {
        let frame = IRFFAudioFrame()
        frame.setSamplesLength(MemoryLayout<Float>.size * 4)
        let initialSamples = try XCTUnwrap(frame.samples)
        frame.outputOffset = 2

        frame.setSamplesLength(MemoryLayout<Float>.size * 2)

        XCTAssertEqual(frame.size, MemoryLayout<Float>.size * 2)
        XCTAssertEqual(frame.outputOffset, 0)
        XCTAssertTrue(frame.samples == initialSamples)
    }

    func testSetSamplesLengthRejectsInvalidLengthsWithoutAllocatingStorage() {
        let frame = IRFFAudioFrame()
        frame.outputOffset = 4

        frame.setSamplesLength(0)

        XCTAssertEqual(frame.size, 0)
        XCTAssertEqual(frame.outputOffset, 0)
        XCTAssertNil(frame.samples)
    }

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRFFAudioFrame.sampleCapacity(forByteLength: MemoryLayout<Float>.size + 1),
            IRFFAudioFramePolicy.sampleCapacity(forByteLength: MemoryLayout<Float>.size + 1)
        )
        XCTAssertEqual(
            IRFFAudioFrame.sampleCapacity(forByteLength: -1),
            IRFFAudioFramePolicy.sampleCapacity(forByteLength: -1)
        )
        XCTAssertEqual(
            IRFFAudioFrame.shouldAllocateSampleBuffer(currentCapacity: 3, requiredCapacity: 4),
            IRFFAudioFramePolicy.shouldAllocateSampleBuffer(currentCapacity: 3, requiredCapacity: 4)
        )
        XCTAssertEqual(
            IRFFAudioFrame.shouldAllocateSampleBuffer(currentCapacity: 4, requiredCapacity: 4),
            IRFFAudioFramePolicy.shouldAllocateSampleBuffer(currentCapacity: 4, requiredCapacity: 4)
        )
    }
}
