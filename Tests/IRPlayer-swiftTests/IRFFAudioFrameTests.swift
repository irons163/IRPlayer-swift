//
//  IRFFAudioFrameTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFAudioFrameTests: XCTestCase {
    func testAudioFrameReportsAudioType() {
        XCTAssertEqual(IRFFAudioFrame().type, .audio)
    }

    func testSampleCapacityRejectsInvalidAndOverflowingByteLengths() {
        XCTAssertNil(
            IRFFAudioFrame.sampleCapacity(forByteLength: 0)
        )
        XCTAssertNil(
            IRFFAudioFrame.sampleCapacity(forByteLength: -1)
        )
        XCTAssertNil(
            IRFFAudioFrame.sampleCapacity(
                forByteLength: Int.max
            )
        )
    }

    func testSampleCapacityRoundsUpToFloatStorage() {
        let stride = MemoryLayout<Float>.stride
        XCTAssertEqual(
            IRFFAudioFrame.sampleCapacity(
                forByteLength: stride
            ),
            1
        )
        XCTAssertEqual(
            IRFFAudioFrame.sampleCapacity(
                forByteLength: stride + 1
            ),
            2
        )
    }

    func testSetSamplesLengthPreparesStorageAndResetsOffset() {
        let frame = IRFFAudioFrame()
        frame.outputOffset = 8

        frame.setSamplesLength(
            MemoryLayout<Float>.stride * 2
        )

        XCTAssertEqual(
            frame.size,
            MemoryLayout<Float>.stride * 2
        )
        XCTAssertEqual(frame.outputOffset, 0)
        XCTAssertEqual(frame.activeSampleCount, 2)
        XCTAssertEqual(frame.sampleCapacity, 2)
    }

    func testMutableBorrowIsBoundedToActiveSamples() throws {
        let frame = IRFFAudioFrame()
        frame.setSamplesLength(
            MemoryLayout<Float>.stride * 3
        )

        var borrowedCount = 0
        XCTAssertTrue(frame.withMutableSamples { samples in
            borrowedCount = samples.count
            samples[0] = 1.25
            samples[1] = -2.5
            samples[2] = 3.75
            return true
        })

        XCTAssertEqual(borrowedCount, 3)
        XCTAssertEqual(
            try sampleValues(from: frame),
            [1.25, -2.5, 3.75]
        )
    }

    func testSnapshotAndMutableBorrowAreUnavailableWithoutActiveStorage() {
        let frame = IRFFAudioFrame()

        XCTAssertNil(frame.sampleSnapshot())
        XCTAssertFalse(
            frame.withMutableSamples { _ in
                XCTFail("missing storage must not invoke its borrow")
                return true
            }
        )
    }

    func testSmallerFrameReusesCapacityWithoutExposingInactiveSamples() throws {
        let frame = makeAudioFrame(
            values: [1, 2, 3, 4]
        )

        frame.setSamplesLength(
            MemoryLayout<Float>.stride * 2
        )

        XCTAssertEqual(frame.sampleCapacity, 4)
        XCTAssertEqual(frame.activeSampleCount, 2)
        XCTAssertEqual(
            try sampleValues(from: frame),
            [1, 2]
        )
    }

    func testLargerFrameGrowsManagedCapacity() {
        let frame = IRFFAudioFrame()
        frame.setSamplesLength(MemoryLayout<Float>.stride)

        frame.setSamplesLength(
            MemoryLayout<Float>.stride * 3
        )

        XCTAssertEqual(frame.sampleCapacity, 3)
        XCTAssertEqual(frame.activeSampleCount, 3)
        XCTAssertTrue(
            frame.withMutableSamples { samples in
                samples[2] = 3.5
                return true
            }
        )
        XCTAssertEqual(frame.sampleSnapshot()?[2], 3.5)
    }

    func testInvalidLengthClearsExistingStorageAndActiveState() {
        let frame = makeAudioFrame(values: [1, 2])
        frame.outputOffset = MemoryLayout<Float>.stride

        frame.setSamplesLength(0)

        XCTAssertEqual(frame.size, 0)
        XCTAssertEqual(frame.outputOffset, 0)
        XCTAssertEqual(frame.activeSampleCount, 0)
        XCTAssertEqual(frame.sampleCapacity, 0)
        XCTAssertNil(frame.sampleSnapshot())
    }

    func testOverflowingLengthClearsExistingStorageAndActiveState() {
        let frame = makeAudioFrame(values: [1, 2])

        frame.setSamplesLength(Int.max)

        XCTAssertEqual(frame.size, 0)
        XCTAssertEqual(frame.outputOffset, 0)
        XCTAssertEqual(frame.activeSampleCount, 0)
        XCTAssertEqual(frame.sampleCapacity, 0)
    }

    func testCopySamplesCopiesCompleteActiveStorage() {
        let frame = makeAudioFrame(
            values: [1, 2, 3, 4]
        )
        var output = [Float](repeating: 0, count: 4)

        let copied = output.withUnsafeMutableBufferPointer {
            buffer in
            frame.copySamples(
                to: buffer.baseAddress!,
                byteOffset: 0,
                byteCount: frame.size
            )
        }

        XCTAssertTrue(copied)
        XCTAssertEqual(output, [1, 2, 3, 4])
    }

    func testCopySamplesCopiesAlignedPartialRange() {
        let frame = makeAudioFrame(
            values: [1, 2, 3, 4]
        )
        var output = [Float](repeating: 0, count: 2)
        let stride = MemoryLayout<Float>.stride

        let copied = output.withUnsafeMutableBufferPointer {
            buffer in
            frame.copySamples(
                to: buffer.baseAddress!,
                byteOffset: stride * 2,
                byteCount: stride * 2
            )
        }

        XCTAssertTrue(copied)
        XCTAssertEqual(output, [3, 4])
    }

    func testCopySamplesCanUseFrozenRenderByteCount() {
        let frame = makeAudioFrame(
            values: [1, 2, 3, 4]
        )
        let admittedByteCount = frame.size
        frame.size = Int.max
        var output = [Float](repeating: 0, count: 4)

        let copied = output.withUnsafeMutableBufferPointer {
            buffer in
            frame.copySamples(
                to: buffer.baseAddress!,
                byteOffset: 0,
                byteCount: admittedByteCount,
                availableByteCount: admittedByteCount
            )
        }

        XCTAssertTrue(copied)
        XCTAssertEqual(output, [1, 2, 3, 4])
    }

    func testCopySamplesRejectsMisalignedAndEmptyRanges() {
        let frame = makeAudioFrame(values: [1, 2])
        var output = [Float](repeating: 9, count: 2)

        output.withUnsafeMutableBufferPointer { buffer in
            XCTAssertFalse(
                frame.copySamples(
                    to: buffer.baseAddress!,
                    byteOffset: 1,
                    byteCount: MemoryLayout<Float>.stride
                )
            )
            XCTAssertFalse(
                frame.copySamples(
                    to: buffer.baseAddress!,
                    byteOffset: 0,
                    byteCount: 0
                )
            )
        }

        XCTAssertEqual(output, [9, 9])
    }

    func testCopySamplesRejectsNegativeOverflowingAndOutOfBoundsRanges() {
        let frame = makeAudioFrame(values: [1, 2])
        var output = [Float](repeating: 9, count: 2)
        let stride = MemoryLayout<Float>.stride

        output.withUnsafeMutableBufferPointer { buffer in
            XCTAssertFalse(
                frame.copySamples(
                    to: buffer.baseAddress!,
                    byteOffset: -stride,
                    byteCount: stride
                )
            )
            XCTAssertFalse(
                frame.copySamples(
                    to: buffer.baseAddress!,
                    byteOffset: stride,
                    byteCount: Int.max - (Int.max % stride)
                )
            )
            XCTAssertFalse(
                frame.copySamples(
                    to: buffer.baseAddress!,
                    byteOffset: stride,
                    byteCount: stride * 2
                )
            )
        }

        XCTAssertEqual(output, [9, 9])
    }

    func testCopySamplesRejectsSizeBeyondManagedStorage() {
        let frame = makeAudioFrame(values: [1, 2])
        let stride = MemoryLayout<Float>.stride
        frame.size = stride * 3
        var output = [Float](repeating: 9, count: 3)

        let copied = output.withUnsafeMutableBufferPointer { buffer in
            frame.copySamples(
                to: buffer.baseAddress!,
                byteOffset: 0,
                byteCount: stride * 3
            )
        }

        XCTAssertFalse(copied)
        XCTAssertEqual(output, [9, 9, 9])
    }

    func testRepeatedReusePublishesOnlyNewestActiveValues() throws {
        let frame = IRFFAudioFrame()

        for iteration in 1...20 {
            let values = (0..<iteration).map {
                Float($0 + iteration)
            }
            prepare(frame, with: values)
            XCTAssertEqual(
                try sampleValues(from: frame),
                values
            )
        }

        XCTAssertEqual(frame.sampleCapacity, 20)
        XCTAssertEqual(frame.activeSampleCount, 20)
    }
}

private func makeAudioFrame(values: [Float]) -> IRFFAudioFrame {
    let frame = IRFFAudioFrame()
    prepare(frame, with: values)
    return frame
}

private func prepare(
    _ frame: IRFFAudioFrame,
    with values: [Float]
) {
    frame.setSamplesLength(
        values.count * MemoryLayout<Float>.stride
    )
    frame.withMutableSamples { samples in
        for (index, value) in values.enumerated() {
            samples[index] = value
        }
        return true
    }
}

private func sampleValues(
    from frame: IRFFAudioFrame
) throws -> [Float] {
    try XCTUnwrap(frame.sampleSnapshot())
}
